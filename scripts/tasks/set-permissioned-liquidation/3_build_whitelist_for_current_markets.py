#!/usr/bin/env python3
"""
Build Safe Transaction Builder bundles for whitelist updates on current markets.

Rules:
- include only markets with hookVersion containing SiloHookV2 or SiloHookV3
- skip markets with hookVersion == legacy (or missing/other)
- for each eligible hook, create grantRole(ALLOWED_ROLE, account) tx for:
  - user-provided addresses (CLI/file)
  - auto-collected liquidation helper addresses from deployments:
    - ManualLiquidationHelper*
    - LiquidationHelper*

Output:
- Safe Transaction Builder JSON file(s) per chain
- when chain has multiple hook owners, one file per owner

python3 scripts/tasks/set-permissioned-liquidation/3_build_whitelist_for_current_markets.py

"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = Path(__file__).resolve().parent

ALLOWED_ROLE = "0xd5dc6b389d0dd5687ab5bd9338f760ebeaff2d2852a93a9a9ebaebbfefc763ac"

CHAIN_IDS: dict[str, int] = {
    "mainnet": 1,
    "optimism": 10,
    "bnb": 56,
    "xdc": 50,
    "arbitrum_one": 42161,
    "avalanche": 43114,
    "sonic": 146,
    "okx": 196,
    "base": 8453,
    "ink": 57073,
    "injective": 1776,
    "megaeth": 4326,
    "mantle": 5000,
}

GRANT_ROLE_ABI: dict[str, Any] = {
    "inputs": [
        {"internalType": "bytes32", "name": "role", "type": "bytes32"},
        {"internalType": "address", "name": "account", "type": "address"},
    ],
    "name": "grantRole",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build whitelist bundles for current markets.")
    parser.add_argument(
        "--markets-json",
        default=str(SCRIPT_DIR / "v3_markets_by_chain.json"),
        help="Input markets JSON enriched with hook fields.",
    )
    parser.add_argument(
        "--addresses-file",
        default="",
        help="Optional file with one whitelist address per line (# comments supported).",
    )
    parser.add_argument(
        "--address",
        action="append",
        default=[],
        help="Whitelist address (can be repeated).",
    )
    parser.add_argument(
        "--output-dir",
        default=str(SCRIPT_DIR / "out"),
        help="Directory for generated Safe bundle files.",
    )
    parser.add_argument(
        "--chain",
        action="append",
        default=[],
        help="Optional chain filter (can be repeated).",
    )
    return parser.parse_args()


def is_address(value: str) -> bool:
    value = value.strip()
    if not value.startswith("0x"):
        return False
    if len(value) != 42:
        return False
    try:
        int(value[2:], 16)
    except ValueError:
        return False
    return True


def normalize_address(value: str) -> str:
    value = value.strip()
    if not is_address(value):
        raise ValueError(f"Invalid address: {value}")
    return value.lower()


def short(addr: str) -> str:
    return f"{addr[:6]}{addr[-4:]}"


def load_extra_addresses(addresses_file: str, cli_addresses: list[str]) -> list[str]:
    out: list[str] = []

    if addresses_file:
        path = Path(addresses_file)
        lines = path.read_text(encoding="utf-8").splitlines()
        for raw in lines:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            out.append(normalize_address(line.split()[0]))

    for addr in cli_addresses:
        out.append(normalize_address(addr))

    dedup = sorted(set(out), key=str.lower)
    return dedup


def load_markets(path: Path) -> dict[str, list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("markets JSON root must be an object")

    out: dict[str, list[dict[str, Any]]] = {}
    for chain, markets in data.items():
        if not isinstance(chain, str) or not isinstance(markets, list):
            continue
        chain_markets: list[dict[str, Any]] = []
        for market in markets:
            if not isinstance(market, dict):
                continue
            chain_markets.append(market)
        out[chain] = chain_markets
    return out


def is_v2_or_v3(hook_version: str | None) -> bool:
    if not hook_version:
        return False
    return ("SiloHookV2" in hook_version) or ("SiloHookV3" in hook_version)


def collect_helpers_for_chain(chain: str) -> list[str]:
    deployments_dir = REPO_ROOT / "silo-core" / "deployments" / chain
    if not deployments_dir.exists():
        return []

    addresses: list[str] = []
    for jf in sorted(deployments_dir.glob("*.json")):
        stem = jf.stem.lower()
        if ("liquidationhelper" not in stem) and ("manualliquidationhelper" not in stem):
            continue
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        addr = data.get("address")
        if isinstance(addr, str) and is_address(addr):
            addresses.append(addr.lower())

    return sorted(set(addresses), key=str.lower)


def build_tx(hook: str, account: str) -> dict[str, Any]:
    return {
        "to": hook,
        "value": "0",
        "data": None,
        "contractMethod": GRANT_ROLE_ABI,
        "contractInputsValues": {
            "role": ALLOWED_ROLE,
            "account": account,
        },
    }


def build_batch(
    chain: str,
    chain_id: int,
    owner: str,
    txs: list[dict[str, Any]],
    whitelist_accounts: list[str],
    hooks: list[str],
) -> dict[str, Any]:
    description_lines = [
        f"Whitelist for current markets on {chain}",
        f"Hook owner (Safe): {owner}",
        f"Hooks in batch: {len(hooks)}",
        f"Whitelisted addresses per hook: {len(whitelist_accounts)}",
        f"Total transactions: {len(txs)}",
        "",
        "Addresses:",
    ] + [f"- {a}" for a in whitelist_accounts]

    return {
        "version": "1.0",
        "chainId": str(chain_id),
        "createdAt": int(time.time() * 1000),
        "meta": {
            "name": f"White List for Current Markets - {chain}",
            "description": "\n".join(description_lines),
            "txBuilderVersion": "1.17.0",
            "createdFromSafeAddress": owner,
            "createdFromOwnerAddress": "",
            "checksum": "",
        },
        "transactions": txs,
    }


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    markets_by_chain = load_markets(Path(args.markets_json))
    extra_addresses = load_extra_addresses(args.addresses_file, args.address)

    chain_filter = {c.strip().lower() for c in args.chain} if args.chain else set()
    generated = 0

    for chain, markets in sorted(markets_by_chain.items(), key=lambda x: x[0]):
        if chain_filter and chain.lower() not in chain_filter:
            continue

        chain_id = CHAIN_IDS.get(chain)
        if chain_id is None:
            print(f"[warn] {chain}: unknown chain id, skipping")
            continue

        eligible_hooks: list[tuple[str, str]] = []
        for market in markets:
            hook = market.get("hook")
            hook_owner = market.get("hookOwner")
            hook_version = market.get("hookVersion")
            if not isinstance(hook, str) or not is_address(hook):
                continue
            if not isinstance(hook_owner, str) or not is_address(hook_owner):
                continue
            if not is_v2_or_v3(hook_version if isinstance(hook_version, str) else None):
                continue
            eligible_hooks.append((hook.lower(), hook_owner.lower()))

        if not eligible_hooks:
            print(f"[info] {chain}: no eligible V2/V3 hooks")
            continue

        helper_addresses = collect_helpers_for_chain(chain)
        whitelist_accounts = sorted(set(extra_addresses + helper_addresses), key=str.lower)
        if not whitelist_accounts:
            print(f"[warn] {chain}: empty whitelist account set, skipping")
            continue

        # Group hooks by multisig owner (one Safe file per owner).
        hooks_by_owner: dict[str, list[str]] = {}
        for hook, owner in sorted(set(eligible_hooks)):
            hooks_by_owner.setdefault(owner, []).append(hook)

        for owner, hooks in sorted(hooks_by_owner.items(), key=lambda x: x[0]):
            txs: list[dict[str, Any]] = []
            for hook in hooks:
                for account in whitelist_accounts:
                    txs.append(build_tx(hook, account))

            batch = build_batch(
                chain=chain,
                chain_id=chain_id,
                owner=owner,
                txs=txs,
                whitelist_accounts=whitelist_accounts,
                hooks=hooks,
            )

            if len(hooks_by_owner) == 1:
                filename = f"White List for Current Markets - {chain}.json"
            else:
                filename = f"White List for Current Markets - {chain} - {short(owner)}.json"

            out_path = output_dir / filename
            out_path.write_text(json.dumps(batch, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

            print(
                f"[ok] {chain} owner={owner} hooks={len(hooks)} accounts={len(whitelist_accounts)} "
                f"tx={len(txs)} -> {out_path.name}"
            )
            generated += 1

    print(f"Generated files: {generated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
