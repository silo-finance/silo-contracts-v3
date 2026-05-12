#!/usr/bin/env python3
"""
Build Safe Transaction Builder bundles for:
- Hook.setGauge(gauge, shareToken)
- PermissionedLiquidationController.grantRole(ALLOWED_ROLE, helper)
- PermissionedLiquidationController.setEnabled(true)

using output from step 4 deployment script.

Input #1 (required):
- permissioned_liquidation_deploy_gauges_by_chain.json

Input #2 (required):
- v3_markets_by_chain.json (source of hookOwner mapping)

Output:
- Safe JSON bundle(s) per chain and per multisig owner.
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
MAX_TX_PER_FILE = 30
SPLIT_TX_CHAINS = {"mainnet"}

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

SET_GAUGE_ABI: dict[str, Any] = {
    "inputs": [
        {"internalType": "contract ISiloIncentivesController", "name": "_gauge", "type": "address"},
        {"internalType": "contract IShareToken", "name": "_shareToken", "type": "address"},
    ],
    "name": "setGauge",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function",
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

SET_ENABLED_ABI: dict[str, Any] = {
    "inputs": [
        {"internalType": "bool", "name": "_enabled", "type": "bool"},
    ],
    "name": "setEnabled",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Safe bundles for setGauge from step 4 output.")
    parser.add_argument(
        "--deploy-json",
        default=str(SCRIPT_DIR / "permissioned_liquidation_deploy_gauges_by_chain.json"),
        help="Input JSON from step 4.",
    )
    parser.add_argument(
        "--markets-json",
        default=str(SCRIPT_DIR / "v3_markets_by_chain.json"),
        help="Markets JSON with hookOwner mapping.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(SCRIPT_DIR / "out"),
        help="Directory for generated Safe bundles.",
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
    if not value.startswith("0x") or len(value) != 42:
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


def load_markets_hook_owners(path: Path) -> dict[str, dict[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("markets JSON root must be an object")

    out: dict[str, dict[str, str]] = {}
    for chain, markets in data.items():
        if not isinstance(chain, str) or not isinstance(markets, list):
            continue
        chain_map: dict[str, str] = {}
        for market in markets:
            if not isinstance(market, dict):
                continue
            hook = market.get("hook")
            owner = market.get("hookOwner")
            if not isinstance(hook, str) or not isinstance(owner, str):
                continue
            if not is_address(hook) or not is_address(owner):
                continue
            chain_map[hook.lower()] = owner.lower()
        out[chain] = chain_map
    return out


def load_deploy_records(path: Path) -> dict[str, list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("deploy JSON root must be an object")

    # Current format (formatVersion + byChain)
    if "byChain" in data and isinstance(data["byChain"], dict):
        by_chain = data["byChain"]
    else:
        by_chain = data

    out: dict[str, list[dict[str, Any]]] = {}
    for chain, records in by_chain.items():
        if not isinstance(chain, str) or not isinstance(records, list):
            continue
        out[chain] = [rec for rec in records if isinstance(rec, dict)]
    return out


def build_tx(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "to": entry["hook"],
        "value": "0",
        "data": None,
        "contractMethod": SET_GAUGE_ABI,
        "contractInputsValues": {
            "_gauge": entry["gauge"],
            "_shareToken": entry["shareToken"],
        },
    }


def build_grant_role_tx(gauge: str, account: str) -> dict[str, Any]:
    return {
        "to": gauge,
        "value": "0",
        "data": None,
        "contractMethod": GRANT_ROLE_ABI,
        "contractInputsValues": {
            "role": ALLOWED_ROLE,
            "account": account,
        },
    }


def build_set_enabled_tx(gauge: str) -> dict[str, Any]:
    return {
        "to": gauge,
        "value": "0",
        "data": None,
        "contractMethod": SET_ENABLED_ABI,
        "contractInputsValues": {
            "_enabled": "true",
        },
    }


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


def split_tx_groups_by_limit(tx_groups: list[list[dict[str, Any]]], max_tx: int) -> list[list[dict[str, Any]]]:
    parts: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []

    for group in tx_groups:
        if not group:
            continue
        if current and (len(current) + len(group) > max_tx):
            parts.append(current)
            current = []

        # Keep per-gauge operations together; if one gauge exceeds limit,
        # we still keep it in one part rather than splitting the gauge group.
        if not current and len(group) > max_tx:
            parts.append(list(group))
            continue

        current.extend(group)

    if current:
        parts.append(current)
    return parts


def build_batch(
    *,
    chain: str,
    chain_id: int,
    owner: str,
    transactions: list[dict[str, Any]],
    source_count: int,
    created_at: int | None = None,
) -> dict[str, Any]:
    return {
        "version": "1.0",
        "chainId": str(chain_id),
        "createdAt": created_at if created_at is not None else int(time.time() * 1000),
        "meta": {
            "name": f"Set Gauge for Current Markets - {chain}",
            "description": (
                f"SetGauge bundle for current markets on {chain}\n"
                f"Hook owner (Safe): {owner}\n"
                f"Source records: {source_count}\n"
                f"Transactions: {len(transactions)}"
            ),
            "txBuilderVersion": "1.17.0",
            "createdFromSafeAddress": owner,
            "createdFromOwnerAddress": "",
            "checksum": "",
        },
        "transactions": transactions,
    }


def load_existing_created_at_if_same_transactions(
    out_path: Path, transactions: list[dict[str, Any]]
) -> int | None:
    if not out_path.exists():
        return None
    try:
        existing = json.loads(out_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(existing, dict):
        return None
    existing_txs = existing.get("transactions")
    existing_created_at = existing.get("createdAt")
    if existing_txs == transactions and isinstance(existing_created_at, int):
        return existing_created_at
    return None


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    hook_owner_by_chain = load_markets_hook_owners(Path(args.markets_json))
    deploy_records_by_chain = load_deploy_records(Path(args.deploy_json))
    chain_filter = {c.strip().lower() for c in args.chain} if args.chain else set()
    validation_errors: list[str] = []

    generated = 0
    for chain, records in sorted(deploy_records_by_chain.items(), key=lambda x: x[0]):
        if chain_filter and chain.lower() not in chain_filter:
            continue

        chain_id = CHAIN_IDS.get(chain)
        if chain_id is None:
            validation_errors.append(f"{chain}: unknown chain id")
            continue

        chain_hook_owner = hook_owner_by_chain.get(chain, {})
        if not chain_hook_owner:
            validation_errors.append(f"{chain}: no hookOwner mapping in markets file")
            continue

        tx_entries_by_owner: dict[str, list[dict[str, str]]] = {}
        source_records_by_owner: dict[str, int] = {}

        for rec in records:
            rec_id = rec.get("id")
            rec_label = f"{chain} id={rec_id if isinstance(rec_id, int) else '-'}"
            entries = rec.get("entries")
            if not isinstance(entries, list):
                validation_errors.append(f"{rec_label}: missing or invalid entries")
                continue

            for entry in entries:
                if not isinstance(entry, dict):
                    validation_errors.append(f"{rec_label}: invalid entry object")
                    continue
                hook = entry.get("hook")
                gauge = entry.get("gauge")
                share_token = entry.get("shareToken")
                share_token_kind = entry.get("shareTokenKind")

                if not isinstance(hook, str) or not isinstance(gauge, str) or not isinstance(share_token, str):
                    validation_errors.append(f"{rec_label}: missing hook/gauge/shareToken")
                    continue
                if not is_address(hook) or not is_address(gauge) or not is_address(share_token):
                    validation_errors.append(f"{rec_label}: invalid hook/gauge/shareToken address")
                    continue

                owner = chain_hook_owner.get(hook.lower())
                if not owner:
                    validation_errors.append(f"{rec_label}: missing hookOwner for hook {hook.lower()}")
                    continue

                tx_entries_by_owner.setdefault(owner, []).append(
                    {
                        "hook": hook.lower(),
                        "gauge": gauge.lower(),
                        "shareToken": share_token.lower(),
                        "shareTokenKind": share_token_kind if isinstance(share_token_kind, str) else "",
                    }
                )
                source_records_by_owner[owner] = source_records_by_owner.get(owner, 0) + 1

        if not tx_entries_by_owner:
            validation_errors.append(f"{chain}: no valid entries to bundle")
            continue

        for owner, entries in sorted(tx_entries_by_owner.items(), key=lambda x: x[0]):
            # deduplicate by functional call identity
            unique_map = {(e["hook"], e["gauge"], e["shareToken"]): e for e in entries}
            unique_entries = sorted(unique_map.values(), key=lambda e: (e["hook"], e["shareToken"], e["gauge"]))
            helper_addresses = collect_helpers_for_chain(chain)
            entries_by_gauge: dict[str, list[dict[str, str]]] = {}
            for e in unique_entries:
                entries_by_gauge.setdefault(e["gauge"], []).append(e)
            gauges_in_order = sorted(entries_by_gauge.keys(), key=str.lower)

            tx_groups: list[list[dict[str, Any]]] = []
            # For easier QA/review, group transactions per gauge:
            # setGauge -> setEnabled(true) -> grantRole helper(s)
            for gauge in gauges_in_order:
                group_txs: list[dict[str, Any]] = []
                for e in entries_by_gauge[gauge]:
                    group_txs.append(build_tx(e))
                group_txs.append(build_set_enabled_tx(gauge))
                for helper in helper_addresses:
                    group_txs.append(build_grant_role_tx(gauge, helper))
                tx_groups.append(group_txs)

            should_split = chain.lower() in SPLIT_TX_CHAINS
            tx_parts = split_tx_groups_by_limit(tx_groups, MAX_TX_PER_FILE) if should_split else [
                [tx for group in tx_groups for tx in group]
            ]

            if len(tx_entries_by_owner) == 1:
                base_filename = f"Set Gauge for Current Markets - {chain}"
            else:
                base_filename = f"Set Gauge for Current Markets - {chain} - {short(owner)}"

            for idx, txs in enumerate(tx_parts, start=1):
                if should_split and len(tx_parts) > 1:
                    filename = f"{base_filename} - Part {idx}.json"
                else:
                    filename = f"{base_filename}.json"

                out_path = output_dir / filename
                created_at = load_existing_created_at_if_same_transactions(out_path, txs)
                batch = build_batch(
                    chain=chain,
                    chain_id=chain_id,
                    owner=owner,
                    transactions=txs,
                    source_count=source_records_by_owner.get(owner, 0),
                    created_at=created_at,
                )
                out_path.write_text(json.dumps(batch, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
                print(
                    f"[ok] {chain} owner={owner} part={idx}/{len(tx_parts)} setGauge={len(unique_entries)} "
                    f"helpers={len(helper_addresses)} gauges={len(gauges_in_order)} tx={len(txs)} -> {out_path.name}"
                )
                generated += 1

    if validation_errors:
        print("[FAIL] Validation errors detected:")
        for err in validation_errors:
            print(f"  - {err}")
        print("Generated files before failure:", generated)
        return 1

    print(f"Generated files: {generated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
