#!/usr/bin/env python3
"""
CI: for each address in silo-core / silo-oracles / silo-vaults deployments JSON for a chain,
find the contract creation in Foundry broadcast **/run-latest.json (same chain id), then fetch
the deployment block timestamp via RPC and fail if older than --max-age-days.

- [ ok ]: contract_name address deploy_time (within limit)
- [FAIL]: address not in any run-latest.json
- [FAIL]: deployment block timestamp older than max age

Uses the same RPC env vars as check_deployments_owner_is_dao.py / version_on_chain.

Example:
  python3 scripts/check_deployments_freshness_from_broadcast.py --chain arbitrum_one --max-age-days 4
  python3 scripts/check_deployments_freshness_from_broadcast.py --chain arbitrum_one --max-age-days 4 \
    --deployment-file silo-core/deployments/arbitrum_one/SiloLens.sol.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

COMPONENT_DEPLOY_ROOTS = {
    "core": "silo-core/deployments",
    "oracle": "silo-oracles/deployments",
    "vaults": "silo-vaults/deployments",
}

BROADCAST_ROOTS = ("silo-core/broadcast", "silo-oracles/broadcast", "silo-vaults/broadcast")

CHAIN_TO_RPC_ENV: dict[str, str] = {
    "arbitrum_one": "RPC_ARBITRUM",
    "avalanche": "RPC_AVALANCHE",
    "base": "RPC_BASE",
    "bnb": "RPC_BNB",
    "injective": "RPC_INJECTIVE",
    "ink": "RPC_INK",
    "mainnet": "RPC_MAINNET",
    "okx": "RPC_OKX",
    "optimism": "RPC_OPTIMISM",
    "sonic": "RPC_SONIC",
    "xdc": "RPC_XDC",
}

CHAIN_TO_CHAIN_ID: dict[str, str] = {
    "mainnet": "1",
    "optimism": "10",
    "bnb": "56",
    "arbitrum_one": "42161",
    "avalanche": "43114",
    "sonic": "146",
    "okx": "196",
    "base": "8453",
    "ink": "57073",
    "injective": "1776",
    "xdc": "50",
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Check deployment block time vs run-latest.json broadcast artifacts."
    )
    p.add_argument("--chain", required=True, help="Chain folder name, e.g. arbitrum_one.")
    p.add_argument(
        "--max-age-days",
        type=float,
        required=True,
        help="Fail if deployment block is older than this many days.",
    )
    p.add_argument("--rpc-url", default=None, help="Override RPC; default from CHAIN_TO_RPC_ENV.")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Only resolve addresses and broadcast txs; do not call RPC or enforce age.",
    )
    p.add_argument(
        "--deployment-file",
        action="append",
        default=[],
        help=(
            "Relative path to changed deployment JSON. Can be repeated. "
            "When provided, only those files are checked."
        ),
    )
    return p.parse_args()


def collect_deployment_addresses(repo_root: Path, chain: str) -> list[tuple[str, str, str]]:
    """(component, contract_name, address_lower) sorted."""
    out: list[tuple[str, str, str]] = []
    for comp, rel in COMPONENT_DEPLOY_ROOTS.items():
        base = repo_root / rel / chain
        if not base.is_dir():
            continue
        for jf in base.glob("*.json"):
            try:
                data = json.loads(jf.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            addr = (data.get("address") or "").strip()
            if not isinstance(addr, str) or not addr.startswith("0x") or len(addr) < 42:
                continue
            name = jf.stem
            if name.endswith(".sol"):
                name = name[:-4]
            out.append((comp, name, addr.lower()))
    out.sort(key=lambda x: (x[0], x[1].lower(), x[2]))
    return out


def collect_deployment_addresses_from_files(
    repo_root: Path, chain: str, files: list[str]
) -> list[tuple[str, str, str]]:
    """(component, contract_name, address_lower) from explicit deployment files."""
    out: list[tuple[str, str, str]] = []

    prefix_to_component = {
        "silo-core/deployments/": "core",
        "silo-oracles/deployments/": "oracle",
        "silo-vaults/deployments/": "vaults",
    }

    for rel in files:
        rel = rel.strip().lstrip("./")
        if not rel.endswith(".json"):
            continue

        component = None
        for prefix, comp in prefix_to_component.items():
            if rel.startswith(prefix):
                component = comp
                break
        if component is None:
            continue

        # Require chain-specific deployment path.
        if f"/deployments/{chain}/" not in rel:
            continue

        jf = repo_root / rel
        if not jf.is_file():
            continue
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        addr = (data.get("address") or "").strip()
        if not isinstance(addr, str) or not addr.startswith("0x") or len(addr) < 42:
            continue
        name = jf.stem
        if name.endswith(".sol"):
            name = name[:-4]
        out.append((component, name, addr.lower()))

    out = sorted(set(out), key=lambda x: (x[0], x[1].lower(), x[2]))
    return out


def _norm_addr(v: object) -> str | None:
    if not isinstance(v, str):
        return None
    s = v.strip().lower()
    if s.startswith("0x") and len(s) >= 42:
        return s
    return None


def find_creation_tx_in_run(
    run_data: dict, target: str
) -> tuple[str, str] | None:
    """
    Return (tx_hash_lower, block_number_hex_with_0x) for a CREATE/CREATE2 that deployed `target`,
    or None. Matches main contractAddress and additionalContracts (address / contractAddress).
    """
    receipts = run_data.get("receipts") or []
    by_tx: dict[str, dict] = {}
    for r in receipts:
        if not isinstance(r, dict):
            continue
        th = r.get("transactionHash")
        if isinstance(th, str) and th.startswith("0x"):
            by_tx[th.lower()] = r

    for tx in run_data.get("transactions") or []:
        if not isinstance(tx, dict):
            continue
        tx_type = tx.get("transactionType")
        if tx_type not in ("CREATE", "CREATE2"):
            continue
        h = tx.get("hash")
        if not isinstance(h, str) or not h.startswith("0x"):
            continue
        hl = h.lower()
        ca = _norm_addr(tx.get("contractAddress"))
        if ca == target:
            rec = by_tx.get(hl)
            if rec:
                bn = rec.get("blockNumber")
                if isinstance(bn, str) and bn.startswith("0x"):
                    return hl, bn
            return None

        for ac in tx.get("additionalContracts") or []:
            if not isinstance(ac, dict):
                continue
            ac_addr = _norm_addr(ac.get("contractAddress")) or _norm_addr(ac.get("address"))
            if ac_addr == target:
                rec = by_tx.get(hl)
                if rec:
                    bn = rec.get("blockNumber")
                    if isinstance(bn, str) and bn.startswith("0x"):
                        return hl, bn
                return None

    return None


def find_deploy_tx_for_address(
    repo_root: Path, chain_id: str, address: str
) -> tuple[str, str, Path] | None:
    """First match across all run-latest.json: (tx_hash, block_number_hex, path)."""
    address = address.lower()
    for rel in BROADCAST_ROOTS:
        base = repo_root / rel
        if not base.is_dir():
            continue
        for run_file in base.glob(f"**/{chain_id}/run-latest.json"):
            try:
                data = json.loads(run_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            hit = find_creation_tx_in_run(data, address)
            if hit:
                tx_hash, block_hex = hit
                return tx_hash, block_hex, run_file
    return None


def rpc_post(rpc_url: str, method: str, params: list) -> dict | None:
    payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    try:
        req = Request(
            rpc_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=45) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError, OSError, json.JSONDecodeError, KeyError):
        return None
    if body.get("error"):
        return None
    return body


def get_block_timestamp(rpc_url: str, block_number_hex: str) -> int | None:
    res = rpc_post(rpc_url, "eth_getBlockByNumber", [block_number_hex, False])
    if not res:
        return None
    r = res.get("result")
    if not isinstance(r, dict):
        return None
    ts = r.get("timestamp")
    if isinstance(ts, str) and ts.startswith("0x"):
        try:
            return int(ts, 16)
        except ValueError:
            return None
    return None


def main() -> int:
    args = parse_args()
    chain = args.chain.strip()
    if chain not in CHAIN_TO_CHAIN_ID:
        print(f"Unknown chain for chain id mapping: {chain}", file=sys.stderr)
        return 1
    if chain not in CHAIN_TO_RPC_ENV:
        print(f"Unknown chain for RPC env: {chain}", file=sys.stderr)
        return 1

    chain_id = CHAIN_TO_CHAIN_ID[chain]
    rpc_url = args.rpc_url or os.environ.get(CHAIN_TO_RPC_ENV[chain], "").strip()
    if not args.dry_run and not rpc_url:
        print(
            f"Missing RPC URL: set {CHAIN_TO_RPC_ENV[chain]} or pass --rpc-url",
            file=sys.stderr,
        )
        return 1

    repo_root = Path(__file__).resolve().parent.parent
    if args.deployment_file:
        entries = collect_deployment_addresses_from_files(repo_root, chain, args.deployment_file)
    else:
        entries = collect_deployment_addresses(repo_root, chain)
    if not entries:
        print(f"[skip] chain={chain} no deployment JSON addresses")
        return 0

    max_age_sec = float(args.max_age_days) * 86400.0
    now = time.time()
    failed = False
    checked_count = 0
    found_in_broadcast_count = 0
    ok_count = 0
    fail_missing_broadcast = 0
    fail_block_timestamp = 0
    fail_too_old = 0

    for comp, name, addr in entries:
        checked_count += 1
        hit = find_deploy_tx_for_address(repo_root, chain_id, addr)
        if not hit:
            msg = (
                f"{comp}/{name} {addr} not in any */broadcast/**/{chain_id}/run-latest.json "
                "(CREATE/CREATE2 + receipts)"
            )
            print(f"[FAIL] {msg}", file=sys.stderr)
            fail_missing_broadcast += 1
            failed = True
            continue

        tx_hash, block_hex, run_path = hit
        found_in_broadcast_count += 1
        rel_run = run_path.relative_to(repo_root)
        if args.dry_run:
            print(f"[dry-run] {comp}/{name} {addr} tx={tx_hash} block={block_hex} via {rel_run}")
            continue

        ts = get_block_timestamp(rpc_url, block_hex)
        if ts is None:
            print(
                f"[FAIL] {comp}/{name} {addr} could not read block timestamp "
                f"(block={block_hex} tx={tx_hash})",
                file=sys.stderr,
            )
            fail_block_timestamp += 1
            failed = True
            continue

        age_sec = now - float(ts)
        if age_sec > max_age_sec:
            age_days = age_sec / 86400.0
            print(
                f"[FAIL] {comp}/{name} {addr} deployed ~{age_days:.2f} days ago "
                f"(limit {args.max_age_days} days) tx={tx_hash} block={block_hex} run={rel_run}",
                file=sys.stderr,
            )
            fail_too_old += 1
            failed = True
            continue

        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        print(
            f"[ ok ] {comp}/{name} {addr} deploy_utc={dt.isoformat()} "
            f"age_days={age_sec/86400:.2f} tx={tx_hash} run={rel_run}"
        )
        ok_count += 1

    total_fail = fail_missing_broadcast + fail_block_timestamp + fail_too_old
    print()
    print("=== Freshness Summary ===")
    print(f"chain: {chain}")
    print(f"checked contracts: {checked_count}")
    print(f"found in run-latest: {found_in_broadcast_count}")
    print(f"ok: {ok_count}")
    print(f"failed: {total_fail}")
    print(f"  - missing in run-latest: {fail_missing_broadcast}")
    print(f"  - block timestamp unreadable: {fail_block_timestamp}")
    print(f"  - older than max age: {fail_too_old}")
    print()

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
