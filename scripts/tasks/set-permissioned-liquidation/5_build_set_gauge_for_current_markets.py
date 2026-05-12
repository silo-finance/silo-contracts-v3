#!/usr/bin/env python3
"""
Build Safe Transaction Builder bundles for Hook.setGauge calls
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

SCRIPT_DIR = Path(__file__).resolve().parent

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
    parser.add_argument(
        "--include-failed",
        action="store_true",
        help="Also include records with success=false from deploy-json.",
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
        normalized: list[dict[str, Any]] = []
        for rec in records:
            if not isinstance(rec, dict):
                continue
            silo_cfg = rec.get("siloConfig")
            entries = rec.get("entries")
            if not isinstance(silo_cfg, str) or not isinstance(entries, list):
                continue
            if not is_address(silo_cfg):
                continue
            normalized.append(rec)
        out[chain] = normalized
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


def build_batch(
    *,
    chain: str,
    chain_id: int,
    owner: str,
    transactions: list[dict[str, Any]],
    source_count: int,
) -> dict[str, Any]:
    return {
        "version": "1.0",
        "chainId": str(chain_id),
        "createdAt": int(time.time() * 1000),
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


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    hook_owner_by_chain = load_markets_hook_owners(Path(args.markets_json))
    deploy_records_by_chain = load_deploy_records(Path(args.deploy_json))
    chain_filter = {c.strip().lower() for c in args.chain} if args.chain else set()

    generated = 0
    for chain, records in sorted(deploy_records_by_chain.items(), key=lambda x: x[0]):
        if chain_filter and chain.lower() not in chain_filter:
            continue

        chain_id = CHAIN_IDS.get(chain)
        if chain_id is None:
            print(f"[warn] {chain}: unknown chain id, skipping")
            continue

        chain_hook_owner = hook_owner_by_chain.get(chain, {})
        if not chain_hook_owner:
            print(f"[warn] {chain}: no hookOwner mapping in markets file, skipping")
            continue

        tx_entries_by_owner: dict[str, list[dict[str, str]]] = {}
        source_records_by_owner: dict[str, int] = {}

        for rec in records:
            success = bool(rec.get("success", True))
            if not success and not args.include_failed:
                continue

            entries = rec.get("entries")
            if not isinstance(entries, list):
                continue

            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                hook = entry.get("hook")
                gauge = entry.get("gauge")
                share_token = entry.get("shareToken")
                share_token_kind = entry.get("shareTokenKind")

                if not isinstance(hook, str) or not isinstance(gauge, str) or not isinstance(share_token, str):
                    continue
                if not is_address(hook) or not is_address(gauge) or not is_address(share_token):
                    continue

                owner = chain_hook_owner.get(hook.lower())
                if not owner:
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
            print(f"[info] {chain}: no entries to bundle")
            continue

        for owner, entries in sorted(tx_entries_by_owner.items(), key=lambda x: x[0]):
            # deduplicate by functional call identity
            unique_map = {(e["hook"], e["gauge"], e["shareToken"]): e for e in entries}
            unique_entries = sorted(unique_map.values(), key=lambda e: (e["hook"], e["shareToken"], e["gauge"]))
            txs = [build_tx(e) for e in unique_entries]

            batch = build_batch(
                chain=chain,
                chain_id=chain_id,
                owner=owner,
                transactions=txs,
                source_count=source_records_by_owner.get(owner, 0),
            )

            if len(tx_entries_by_owner) == 1:
                filename = f"Set Gauge for Current Markets - {chain}.json"
            else:
                filename = f"Set Gauge for Current Markets - {chain} - {short(owner)}.json"

            out_path = output_dir / filename
            out_path.write_text(json.dumps(batch, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(f"[ok] {chain} owner={owner} tx={len(txs)} -> {out_path.name}")
            generated += 1

    print(f"Generated files: {generated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
