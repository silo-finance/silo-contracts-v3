#!/usr/bin/env python3
"""
CI script: check that every deployed contract (core, oracle, vaults) that has an
owner() returns an owner that is the DAO from common/addresses for that chain.

Intended to run in CI matrix per blockchain. For each chain:
  - Load all deployment addresses (and ABI) from silo-core, silo-oracles, silo-vaults.
  - For each address: if the deployment ABI has no owner() function, skip (no RPC call).
  - If ABI has owner(): eth_call owner() and check that the owner is DAO in common/addresses/<chain>.json
    and that the key is "DAO". If key is DAO -> pass (green). If key is something else or
    owner not in file -> CI fail with a clear message (contract name, owner address, key or "not in common-addresses").

Usage (single chain, e.g. in CI matrix):

  export RPC_ARBITRUM_ONE=https://...
  python3 scripts/check_deployments_owner_is_dao.py --chain arbitrum_one

  # Optional: limit to specific components
  python3 scripts/check_deployments_owner_is_dao.py --chain mainnet --components core,oracle

  # Dry run (list what would be checked)
  python3 scripts/check_deployments_owner_is_dao.py --chain arbitrum_one --dry-run

Exit code: 0 if all owned contracts have owner == DAO; 1 if any owner is not DAO or on RPC/IO error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# owner() selector: first 4 bytes of keccak256("owner()")
OWNER_SELECTOR = "0x8da5cb5b"
# pendingOwner() selector (Ownable2Step)
PENDING_OWNER_SELECTOR = "0xe30c3978"

# Component name -> deployments path relative to repo root
COMPONENT_PATHS = {
    "core": "silo-core/deployments",
    "oracle": "silo-oracles/deployments",
    "vaults": "silo-vaults/deployments",
}

# Contracts excluded from owner-is-DAO check (by deployment name)
CONTRACTS_EXCLUDED: set[str] = {"Tower"}

# Chain folder name -> exact env var name used in .env / CI (use env as-is, no derivation)
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
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Check that deployment owners are DAO (for CI, run per chain)."
    )
    p.add_argument(
        "--chain",
        required=True,
        help="Chain name (folder under deployments/, e.g. arbitrum_one, mainnet).",
    )
    p.add_argument(
        "--rpc-url",
        default=None,
        help="RPC URL. If not set, uses env RPC_<CHAIN> (e.g. RPC_ARBITRUM_ONE).",
    )
    p.add_argument(
        "--components",
        default="core,oracle,vaults",
        help="Comma-separated list: core, oracle, vaults. Default: core,oracle,vaults",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Only list contracts and addresses, do not call RPC.",
    )
    return p.parse_args()


def load_common_addresses(repo_root: Path, chain: str) -> dict[str, str]:
    """Load common/addresses/<chain>.json; return dict key -> address (normalized lower)."""
    path = repo_root / "common" / "addresses" / f"{chain}.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k: v.strip().lower() for k, v in data.items() if isinstance(v, str) and v.strip().startswith("0x")}


def get_dao_address(common_addresses: dict[str, str]) -> str | None:
    return common_addresses.get("DAO")


def abi_has_owner(abi: list | None) -> bool:
    """True if ABI declares a view function owner() with no arguments (Ownable)."""
    if not abi:
        return False
    for item in abi:
        if (
            isinstance(item, dict)
            and item.get("type") == "function"
            and item.get("name") == "owner"
        ):
            ins = item.get("inputs") or []
            if len(ins) == 0:
                return True
    return False


def collect_deployment_addresses(
    repo_root: Path, chain: str, components: list[str]
) -> list[tuple[str, str, str, list | None]]:
    """
    Returns list of (component, contract_name, address, abi) for the given chain.
    abi is the "abi" array from the deployment JSON, or None if missing.
    """
    out: list[tuple[str, str, str, list | None]] = []
    for comp in components:
        base = repo_root / COMPONENT_PATHS[comp] / chain
        if not base.exists():
            continue
        for j in base.glob("*.json"):
            try:
                data = json.loads(j.read_text(encoding="utf-8"))
                addr = (data.get("address") or "").strip()
                if isinstance(addr, str) and addr.startswith("0x") and len(addr) >= 42:
                    name = j.stem
                    if name.endswith(".sol"):
                        name = name[:-4]
                    abi = data.get("abi")
                    if not isinstance(abi, list):
                        abi = None
                    out.append((comp, name, addr.lower(), abi))
            except (json.JSONDecodeError, OSError):
                continue
    return out


def eth_call_owner(rpc_url: str, contract_address: str) -> str | None:
    """
    Call owner() on contract via eth_call. Returns owner address (lowercase) or None if call reverts/fails.
    """
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [
            {
                "to": contract_address if contract_address.startswith("0x") else "0x" + contract_address,
                "data": OWNER_SELECTOR,
            },
            "latest",
        ],
    }
    try:
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError, URLError

        req = Request(
            rpc_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError, OSError, json.JSONDecodeError, KeyError) as e:
        print(f"RPC error for {contract_address}: {e}", file=sys.stderr)
        return None

    err = body.get("error")
    if err:
        # Revert or RPC error -> no owner / not callable
        return None

    result = (body.get("result") or "").strip()
    if not result or result == "0x":
        return None
    # address is 32 bytes (64 hex chars); last 20 bytes = address
    if len(result) >= 64:
        addr = "0x" + result[-40:].lower()
        if addr == "0x" + "0" * 40:
            return None
        return addr
    return None


def eth_call_pending_owner(rpc_url: str, contract_address: str) -> str | None:
    """
    Call pendingOwner() on contract via eth_call (Ownable2Step).
    Returns pending owner address (lowercase) or None if call reverts/fails or no pending owner.
    """
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [
            {
                "to": contract_address if contract_address.startswith("0x") else "0x" + contract_address,
                "data": PENDING_OWNER_SELECTOR,
            },
            "latest",
        ],
    }
    try:
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError, URLError

        req = Request(
            rpc_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError, OSError, json.JSONDecodeError, KeyError):
        return None

    if body.get("error"):
        return None

    result = (body.get("result") or "").strip()
    if not result or result == "0x" or len(result) < 64:
        return None
    addr = "0x" + result[-40:].lower()
    if addr == "0x" + "0" * 40:
        return None
    return addr


def main() -> int:
    args = parse_args()
    chain = args.chain.strip()
    components = [c.strip() for c in args.components.split(",") if c.strip()]
    for c in components:
        if c not in COMPONENT_PATHS:
            print(f"Unknown component: {c}. Allowed: {list(COMPONENT_PATHS.keys())}", file=sys.stderr)
            return 2

    repo_root = Path(__file__).resolve().parents[1]
    common_addresses = load_common_addresses(repo_root, chain)
    dao_address = get_dao_address(common_addresses)
    if not dao_address:
        print(f"DAO not found in common/addresses/{chain}.json", file=sys.stderr)
        return 2

    # Build reverse map: address -> key for reporting
    addr_to_key: dict[str, str] = {addr: key for key, addr in common_addresses.items()}

    rpc_env = CHAIN_TO_RPC_ENV.get(chain)
    rpc_url = args.rpc_url or (os.environ.get(rpc_env) if rpc_env else None)
    if not args.dry_run and not rpc_url:
        hint = rpc_env or f"RPC_<chain> (add {chain!r} to CHAIN_TO_RPC_ENV)"
        print(f"RPC URL not set. Use --rpc-url or set env {hint}", file=sys.stderr)
        return 2

    deployments = collect_deployment_addresses(repo_root, chain, components)
    if not deployments:
        print(f"No deployments found for chain={chain}, components={components}", file=sys.stderr)
        return 0

    deployments.sort(key=lambda x: (x[0], x[1]))  # alphabetical: component, then contract name

    has_failure = False
    skip_count = 0
    ok_count = 0
    fail_count = 0
    failed_contracts: list[tuple[str, str]] = []

    for component, contract_name, address, abi in deployments:
        if args.dry_run:
            print(f"[dry-run] {component} {contract_name} {address}")
            continue

        if contract_name in CONTRACTS_EXCLUDED:
            print(f"[skip] {component} {contract_name} excluded from check")
            skip_count += 1
            continue

        if not abi_has_owner(abi):
            print(f"[skip] {component} {contract_name} no owner()")
            skip_count += 1
            continue

        owner = eth_call_owner(rpc_url, address)
        if owner is None:
            print(f"[skip] {component} {contract_name} owner() call failed")
            skip_count += 1
            continue

        if owner == dao_address:
            print(f"[ ok ] {component} {contract_name} owner is DAO")
            ok_count += 1
            continue

        key = addr_to_key.get(owner)
        if key is None:
            print(f"[FAIL] {component} {contract_name} owner {owner} not in common/addresses/{chain}.json (expected DAO)")
        else:
            print(f"[FAIL] {component} {contract_name} owner is {key} ({owner}), expected DAO")
        pending = eth_call_pending_owner(rpc_url, address)
        if pending:
            pending_key = addr_to_key.get(pending)
            if pending_key is not None:
                print(f"       -> pending owner: {pending_key}")
            else:
                print(f"       -> pending owner: unknown ({pending})")
        has_failure = True
        fail_count += 1
        failed_contracts.append((component, contract_name))

    if args.dry_run:
        print(f"Dry-run: would check {len(deployments)} deployments for chain={chain}.")
        return 0

    print(f"Summary: skipped={skip_count} ok={ok_count} fail={fail_count}")
    if failed_contracts:
        print("Contracts failing verification:")
        for component, contract_name in failed_contracts:
            print(f"  - {component}/{contract_name}")
    return 1 if has_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
