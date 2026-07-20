#!/usr/bin/env python3
"""
Build Safe Transaction Builder batches to revoke OLD helpers and grant NEW helpers
on hook/controller whitelists discovered by 1_discover_whitelists.py.

Default scope:
  only contracts that already have a non-empty ALLOWED_ROLE whitelist
  (hook and/or PermissionedLiquidationController — both can apply on one market).
  Public markets / empty whitelists are ignored.

Usage:
  python3 scripts/tasks/migrate-liquidation-helpers/2_build_migration_batches.py --chain mainnet
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_OUT_DIR = SCRIPT_DIR / "out"

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

REVOKE_ROLE_ABI: dict[str, Any] = {
    "inputs": [
        {"internalType": "bytes32", "name": "role", "type": "bytes32"},
        {"internalType": "address", "name": "account", "type": "address"},
    ],
    "name": "revokeRole",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function",
}

DEFAULT_MAX_TX = 80


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Safe batches for liquidation helper migration.")
    parser.add_argument("--chain", required=True, help="Chain alias.")
    parser.add_argument(
        "--inventory",
        type=Path,
        default=None,
        help="Path to inventory_<chain>.json (default: out/inventory_<chain>.json).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUT_DIR})",
    )
    parser.add_argument(
        "--max-tx",
        type=int,
        default=DEFAULT_MAX_TX,
        help=f"Max transactions per Safe batch file (default: {DEFAULT_MAX_TX}).",
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
    return value.strip().lower()


def short(addr: str) -> str:
    a = addr.lower()
    return f"{a[:6]}{a[-4:]}"


def build_role_tx(to: str, method_abi: dict[str, Any], account: str) -> dict[str, Any]:
    return {
        "to": to,
        "value": "0",
        "data": None,
        "contractMethod": method_abi,
        "contractInputsValues": {
            "role": ALLOWED_ROLE,
            "account": account,
        },
    }


def tx_key(tx: dict[str, Any]) -> tuple[str, str, str]:
    method = tx["contractMethod"]["name"]
    account = normalize_address(tx["contractInputsValues"]["account"])
    return (normalize_address(tx["to"]), method, account)


def split_txs(txs: list[dict[str, Any]], max_tx: int) -> list[list[dict[str, Any]]]:
    if max_tx <= 0:
        return [txs]
    parts: list[list[dict[str, Any]]] = []
    for i in range(0, len(txs), max_tx):
        parts.append(txs[i : i + max_tx])
    return parts or [[]]


def build_batch(
    *,
    chain: str,
    chain_id: int,
    owner: str,
    transactions: list[dict[str, Any]],
    target_count: int,
) -> dict[str, Any]:
    return {
        "version": "1.0",
        "chainId": str(chain_id),
        "createdAt": int(time.time() * 1000),
        "meta": {
            "name": f"Migrate Liquidation Helpers - {chain}",
            "description": (
                f"Migrate liquidation helpers on {chain}\n"
                f"Owner (Safe): {owner}\n"
                f"Targets touched: {target_count}\n"
                f"Transactions: {len(transactions)}\n"
                f"Operations: revokeRole(OLD) + grantRole(NEW) where needed"
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
    chain = args.chain.strip().lower()
    chain_id = CHAIN_IDS.get(chain)
    if chain_id is None:
        print(f"[FAIL] unknown chain alias: {chain}")
        return 1

    inventory_path = args.inventory or (DEFAULT_OUT_DIR / f"inventory_{chain}.json")
    if not inventory_path.is_file():
        print(f"[FAIL] inventory not found: {inventory_path}")
        return 1

    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    helpers = inventory.get("helpers") or []
    if not isinstance(helpers, list):
        print("[FAIL] inventory.helpers must be a list")
        return 1

    new_helpers: list[str] = []
    old_helpers: list[str] = []
    seen_new: set[str] = set()
    seen_old: set[str] = set()
    for helper in helpers:
        if not isinstance(helper, dict):
            continue
        new_addr = helper.get("new")
        if isinstance(new_addr, str) and is_address(new_addr):
            n = normalize_address(new_addr)
            if n not in seen_new:
                seen_new.add(n)
                new_helpers.append(n)
        old_addr = helper.get("old")
        if isinstance(old_addr, str) and is_address(old_addr):
            o = normalize_address(old_addr)
            if o not in seen_old:
                seen_old.add(o)
                old_helpers.append(o)

    targets = inventory.get("targets") or []
    if not isinstance(targets, list):
        print("[FAIL] inventory.targets must be a list")
        return 1

    print(
        "[info] default scope: only hook/controller contracts with an already-set "
        "non-empty ALLOWED_ROLE whitelist (from inventory.targets[].members)"
    )
    print(f"[info] inventory targets total: {len(targets)}")

    # Group txs by admin
    txs_by_owner: dict[str, list[dict[str, Any]]] = {}
    targets_by_owner: dict[str, set[str]] = {}
    seen_keys: set[tuple[str, str, str]] = set()
    skipped_empty = 0
    skipped_no_admin = 0
    skipped_up_to_date = 0
    considered = 0

    for target in targets:
        if not isinstance(target, dict):
            continue
        to = target.get("target")
        admin = target.get("admin")
        if not isinstance(to, str) or not is_address(to):
            continue
        if not isinstance(admin, str) or not is_address(admin):
            skipped_no_admin += 1
            print(f"[warn] skip target without admin: {to}")
            continue

        to_n = normalize_address(to)
        admin_n = normalize_address(admin)
        members = {
            normalize_address(a)
            for a in (target.get("members") or [])
            if isinstance(a, str) and is_address(a)
        }

        # Default: ignore contracts without an existing whitelist (empty members).
        # Hook vs controller does not matter — whichever already has members is in scope.
        if not members:
            skipped_empty += 1
            continue

        considered += 1
        revoke_accounts = sorted(a for a in old_helpers if a in members)
        grant_accounts = sorted(a for a in new_helpers if a not in members)

        if not revoke_accounts and not grant_accounts:
            skipped_up_to_date += 1
            continue

        owner_txs = txs_by_owner.setdefault(admin_n, [])
        targets_by_owner.setdefault(admin_n, set()).add(to_n)
        target_type = target.get("targetType") or "?"
        print(
            f"[ok] include {target_type} {to_n}: members={len(members)} "
            f"revoke={len(revoke_accounts)} grant={len(grant_accounts)}"
        )

        for account in revoke_accounts:
            tx = build_role_tx(to_n, REVOKE_ROLE_ABI, account)
            key = tx_key(tx)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            owner_txs.append(tx)

        for account in grant_accounts:
            tx = build_role_tx(to_n, GRANT_ROLE_ABI, account)
            key = tx_key(tx)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            owner_txs.append(tx)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    generated = 0

    for owner, txs in sorted(txs_by_owner.items(), key=lambda x: x[0]):
        if not txs:
            continue
        parts = split_txs(txs, args.max_tx)
        target_count = len(targets_by_owner.get(owner, set()))
        multi_owner = len(txs_by_owner) > 1

        for idx, part_txs in enumerate(parts, start=1):
            batch = build_batch(
                chain=chain,
                chain_id=chain_id,
                owner=owner,
                transactions=part_txs,
                target_count=target_count,
            )

            if multi_owner and len(parts) == 1:
                filename = f"Migrate Liquidation Helpers - {chain} - {short(owner)}.json"
            elif multi_owner:
                filename = (
                    f"Migrate Liquidation Helpers - {chain} - {short(owner)} - Part {idx}.json"
                )
            elif len(parts) > 1:
                filename = f"Migrate Liquidation Helpers - {chain} - {short(owner)} - Part {idx}.json"
            else:
                filename = f"Migrate Liquidation Helpers - {chain} - {short(owner)}.json"

            out_path = args.output_dir / filename
            out_path.write_text(json.dumps(batch, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(
                f"[ok] owner={owner} targets={target_count} tx={len(part_txs)} "
                f"part={idx}/{len(parts)} -> {out_path.name}"
            )
            generated += 1

    print(
        f"[summary] with_whitelist={considered} skipped_empty={skipped_empty} "
        f"skipped_up_to_date={skipped_up_to_date} skipped_no_admin={skipped_no_admin}"
    )
    print(
        f"[done] generated files: {generated} | new={len(new_helpers)} old={len(old_helpers)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
