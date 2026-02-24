#!/usr/bin/env python3
"""
CI script: check that every deployed contract (core, oracle, vaults) that uses
OpenZeppelin Access Control has the DEFAULT_ADMIN_ROLE holder equal to DAO from
common/addresses for that chain.

Uses AccessControlEnumerable: getRoleMemberCount(DEFAULT_ADMIN_ROLE) and
getRoleMember(DEFAULT_ADMIN_ROLE, 0). DEFAULT_ADMIN_ROLE = bytes32(0).
If the contract has no such methods (revert) -> SKIP. If admin != DAO -> FAIL.

Output and behaviour mirror check_deployments_owner_is_dao.py: one line per
contract ([OK] / [skip] / [FAIL]), no summary, exit 1 if any FAIL.

Usage:

  python3 scripts/check_deployments_admin_is_dao.py --chain arbitrum_one
  python3 scripts/check_deployments_admin_is_dao.py --chain mainnet --components core,oracle
  python3 scripts/check_deployments_admin_is_dao.py --chain arbitrum_one --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# OpenZeppelin AccessControl: DEFAULT_ADMIN_ROLE = bytes32(0)
DEFAULT_ADMIN_ROLE_HEX = "0" * 64

# getRoleMemberCount(bytes32) selector
GET_ROLE_MEMBER_COUNT_SELECTOR = "0xca15c873"
# getRoleMember(bytes32,uint256) selector
GET_ROLE_MEMBER_SELECTOR = "0x9010d07c"

COMPONENT_PATHS = {
    "core": "silo-core/deployments",
    "oracle": "silo-oracles/deployments",
    "vaults": "silo-vaults/deployments",
}

CONTRACTS_EXCLUDED: set[str] = {"Tower"}

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
        description="Check that deployment admins (DEFAULT_ADMIN_ROLE) are DAO (for CI, run per chain)."
    )
    p.add_argument("--chain", required=True, help="Chain name (e.g. arbitrum_one, mainnet).")
    p.add_argument("--rpc-url", default=None, help="RPC URL. If not set, uses env from CHAIN_TO_RPC_ENV.")
    p.add_argument("--components", default="core,oracle,vaults", help="Comma-separated: core, oracle, vaults.")
    p.add_argument("--dry-run", action="store_true", help="Only list contracts, do not call RPC.")
    return p.parse_args()


def load_common_addresses(repo_root: Path, chain: str) -> dict[str, str]:
    path = repo_root / "common" / "addresses" / f"{chain}.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k: v.strip().lower() for k, v in data.items() if isinstance(v, str) and v.strip().startswith("0x")}


def get_dao_address(common_addresses: dict[str, str]) -> str | None:
    return common_addresses.get("DAO")


def collect_deployment_addresses(
    repo_root: Path, chain: str, components: list[str]
) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []
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
                    out.append((comp, name, addr.lower()))
            except (json.JSONDecodeError, OSError):
                continue
    return out


def _eth_call(rpc_url: str, to: str, data: str) -> str | None:
    to = to if to.startswith("0x") else "0x" + to
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [{"to": to, "data": data}, "latest"],
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
    return result if result else None


def eth_call_admin(rpc_url: str, contract_address: str) -> str | None:
    """
    Get first DEFAULT_ADMIN_ROLE holder via getRoleMemberCount + getRoleMember.
    Returns address (lowercase) or None if contract has no AccessControlEnumerable / revert.
    """
    # getRoleMemberCount(DEFAULT_ADMIN_ROLE): selector + bytes32(0)
    data_count = GET_ROLE_MEMBER_COUNT_SELECTOR + DEFAULT_ADMIN_ROLE_HEX
    result = _eth_call(rpc_url, contract_address, data_count)
    if result is None:
        return None
    # uint256: 32 bytes = 64 hex chars
    if len(result) < 64:
        return None
    count_hex = result[-64:]
    try:
        count = int(count_hex, 16)
    except ValueError:
        return None
    if count == 0:
        return None
    # getRoleMember(DEFAULT_ADMIN_ROLE, 0): selector + role (32 bytes) + index (32 bytes = 0)
    data_member = GET_ROLE_MEMBER_SELECTOR + DEFAULT_ADMIN_ROLE_HEX + "0" * 64
    result = _eth_call(rpc_url, contract_address, data_member)
    if result is None or len(result) < 64:
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

    for component, contract_name, address in deployments:
        if args.dry_run:
            print(f"[dry-run] {component} {contract_name} {address}")
            continue

        if contract_name in CONTRACTS_EXCLUDED:
            print(f"[skip] {component} {contract_name} excluded from check")
            continue

        admin = eth_call_admin(rpc_url, address)
        if admin is None:
            print(f"[skip] {component} {contract_name} no DEFAULT_ADMIN_ROLE / getRoleMember")
            continue

        if admin == dao_address:
            print(f"[OK] {component} {contract_name} admin is DAO")
            continue

        key = addr_to_key.get(admin)
        if key is None:
            print(f"[FAIL] {component} {contract_name} admin {admin} not in common/addresses/{chain}.json (expected DAO)")
        else:
            print(f"[FAIL] {component} {contract_name} admin is {key} ({admin}), expected DAO")
        has_failure = True

    if args.dry_run:
        print(f"Dry-run: would check {len(deployments)} deployments for chain={chain}.")
        return 0

    return 1 if has_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
