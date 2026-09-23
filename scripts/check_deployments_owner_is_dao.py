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
import sys
from pathlib import Path
from typing import Any
from rpc_multicall import (
    format_rpc_error,
    multicall_eth_calls,
    resolve_primary_rpc_url,
    rpc_batch_request,
    rpc_preflight,
)

# owner() selector: first 4 bytes of keccak256("owner()")
OWNER_SELECTOR = "0x8da5cb5b"
# pendingOwner() selector (Ownable2Step)
PENDING_OWNER_SELECTOR = "0xe30c3978"
# acceptOwnership() selector (Ownable2Step)
ACCEPT_OWNERSHIP_SELECTOR = "0x79ba5097"
# EIP-1967 slots
EIP1967_IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
EIP1967_ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
EIP1967_BEACON_SLOT = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"

# Component name -> deployments path relative to repo root
COMPONENT_PATHS = {
    "core": "silo-core/deployments",
    "oracle": "silo-oracles/deployments",
    "vaults": "silo-vaults/deployments",
}

# Contracts excluded from owner-is-DAO check (by deployment name)
CONTRACTS_EXCLUDED: set[str] = {"Tower", "VirtualTokenPrice"}

# Chain folder name -> exact env var name used in .env / CI (use env as-is, no derivation)
CHAIN_TO_RPC_ENV: dict[str, str] = {
    "arbitrum_one": "RPC_ARBITRUM",
    "avalanche": "RPC_AVALANCHE",
    "base": "RPC_BASE",
    "bnb": "RPC_BNB",
    "injective": "RPC_INJECTIVE",
    "ink": "RPC_INK",
    "mainnet": "RPC_MAINNET",
    "mantle": "RPC_MANTLE",
    "megaeth": "RPC_MEGAETH",
    "okx": "RPC_OKX",
    "optimism": "RPC_OPTIMISM",
    "pharos": "RPC_PHAROS",
    "sonic": "RPC_SONIC",
    "xdc": "RPC_XDC",
}

# Chain folder name -> display name for summary lists
CHAIN_DISPLAY_NAMES: dict[str, str] = {
    "arbitrum_one": "Arbitrum",
    "avalanche": "Avalanche",
    "base": "Base",
    "bnb": "BNB",
    "injective": "Injective",
    "ink": "Ink",
    "mainnet": "Mainnet",
    "mantle": "Mantle",
    "megaeth": "MegaETH",
    "okx": "OKX",
    "optimism": "Optimism",
    "pharos": "Pharos",
    "sonic": "Sonic",
    "xdc": "XDC",
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
    p.add_argument(
        "--no-fail",
        action="store_true",
        help="Always return exit code 0 (useful when aggregating results in a separate CI job).",
    )
    p.add_argument(
        "--output-json-file",
        metavar="PATH",
        help="Write machine-readable summary JSON to PATH.",
    )
    return p.parse_args()


def _write_json_report(
    path: str,
    *,
    check_type: str,
    chain: str,
    chain_label: str,
    skipped: int,
    ok: int,
    fail: int,
    failed_contracts: list[tuple[str, str, str]],
    pending_owner_contracts: list[tuple[str, str, str, str]],
    error: str | None = None,
) -> None:
    data: dict[str, Any] = {
        "check_type": check_type,
        "chain": chain,
        "chain_label": chain_label,
        "summary": {"skipped": skipped, "ok": ok, "fail": fail},
        "has_failure": bool(fail > 0 or error),
        "failed_contracts": [
            {"component": component, "contract_name": contract_name, "address": address}
            for component, contract_name, address in failed_contracts
        ],
        "pending_owner_contracts": [
            {
                "component": component,
                "contract_name": contract_name,
                "address": address,
                "pending_owner": pending_owner,
            }
            for component, contract_name, address, pending_owner in pending_owner_contracts
        ],
        "error": error,
    }
    Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_common_addresses(repo_root: Path, chain: str) -> dict[str, str]:
    """Load common/addresses/<chain>.json; return dict key -> address (normalized lower)."""
    path = repo_root / "common" / "addresses" / f"{chain}.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k: v.strip().lower() for k, v in data.items() if isinstance(v, str) and v.strip().startswith("0x")}


def get_dao_addresses(common_addresses: dict[str, str]) -> set[str]:
    """
    Return set of DAO addresses that are allowed to own contracts.
    Includes both current DAO and legacy DAO_OLD when present.
    """
    addrs: set[str] = set()
    dao = common_addresses.get("DAO")
    if dao:
        addrs.add(dao)
    dao_old = common_addresses.get("DAO_OLD")
    if dao_old:
        addrs.add(dao_old)
    return addrs


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


def _extract_address_from_32byte_hex(value: str | None) -> str | None:
    """Extract address from 32-byte hex word (last 20 bytes)."""
    if not value or not isinstance(value, str):
        return None
    data = value.strip().lower()
    if not data.startswith("0x"):
        return None
    hex_part = data[2:]
    if len(hex_part) != 64:
        return None
    addr = "0x" + hex_part[-40:]
    if addr == "0x" + "0" * 40:
        return None
    return addr


def detect_proxy_info(chain: str, rpc_url: str, contract_address: str) -> tuple[bool, str]:
    """
    Probe proxy-related storage slots (EIP-1967).
    Returns (is_proxy, details_string).
    """
    addr = contract_address if contract_address.startswith("0x") else "0x" + contract_address
    calls = [
        (1, "eth_getStorageAt", [addr, EIP1967_IMPLEMENTATION_SLOT, "latest"]),
        (2, "eth_getStorageAt", [addr, EIP1967_ADMIN_SLOT, "latest"]),
        (3, "eth_getStorageAt", [addr, EIP1967_BEACON_SLOT, "latest"]),
    ]
    by_id, err = rpc_batch_request(rpc_url, calls, timeout=45, chain=chain)
    if err:
        return False, f"proxy_probe_failed ({err})"
    impl_body = by_id.get(1)
    if not impl_body:
        return False, "proxy_probe_failed (missing_implementation_response)"
    if impl_body.get("error"):
        return False, f"proxy_probe_failed (rpc_error {format_rpc_error(impl_body.get('error'))})"

    impl = _extract_address_from_32byte_hex(impl_body.get("result"))

    admin = None
    admin_body = by_id.get(2)
    if admin_body and not admin_body.get("error"):
        admin = _extract_address_from_32byte_hex(admin_body.get("result"))

    beacon = None
    beacon_body = by_id.get(3)
    if beacon_body and not beacon_body.get("error"):
        beacon = _extract_address_from_32byte_hex(beacon_body.get("result"))

    if impl or beacon:
        return True, f"is_proxy implementation={impl or 'none'} admin={admin or 'none'} beacon={beacon or 'none'}"

    return False, "not_proxy_eip1967_slots_empty"


def _decode_owner_like_result(result: str | None, empty_reason: str) -> tuple[str | None, str | None]:
    """Decode address-returning owner-like call result."""
    result = (result or "").strip()
    if not result or result == "0x":
        return None, empty_reason
    if not result.startswith("0x"):
        return None, f"invalid_result_format {result[:60]}"
    if len(result) < 64:
        return None, f"short_result len={len(result)} value={result}"
    addr = "0x" + result[-40:].lower()
    if addr == "0x" + "0" * 40:
        return None, "owner_is_zero_address"
    return addr, None


def main() -> int:
    args = parse_args()
    chain = args.chain.strip()
    components = [c.strip() for c in args.components.split(",") if c.strip()]
    for c in components:
        if c not in COMPONENT_PATHS:
            print(f"Unknown component: {c}. Allowed: {list(COMPONENT_PATHS.keys())}", file=sys.stderr)
            if args.output_json_file:
                _write_json_report(
                    args.output_json_file,
                    check_type="owner",
                    chain=chain,
                    chain_label=CHAIN_DISPLAY_NAMES.get(chain, chain),
                    skipped=0,
                    ok=0,
                    fail=1,
                    failed_contracts=[],
                    pending_owner_contracts=[],
                    error=f"Unknown component: {c}",
                )
            return 2

    repo_root = Path(__file__).resolve().parents[1]
    common_addresses = load_common_addresses(repo_root, chain)
    dao_addresses = get_dao_addresses(common_addresses)
    if not dao_addresses:
        print(f"DAO/DAO_OLD not found in common/addresses/{chain}.json", file=sys.stderr)
        if args.output_json_file:
            _write_json_report(
                args.output_json_file,
                check_type="owner",
                chain=chain,
                chain_label=CHAIN_DISPLAY_NAMES.get(chain, chain),
                skipped=0,
                ok=0,
                fail=1,
                failed_contracts=[],
                pending_owner_contracts=[],
                error=f"DAO/DAO_OLD not found in common/addresses/{chain}.json",
            )
        return 2

    # Build reverse map: address -> key for reporting
    addr_to_key: dict[str, str] = {addr: key for key, addr in common_addresses.items()}

    rpc_env = CHAIN_TO_RPC_ENV.get(chain)
    env_rpc_url = (os.environ.get(rpc_env) or "").strip() if rpc_env else None
    rpc_url = resolve_primary_rpc_url(chain, args.rpc_url or env_rpc_url)
    if not args.dry_run and not rpc_url:
        hint = rpc_env or f"RPC_<chain> (add {chain!r} to CHAIN_TO_RPC_ENV)"
        print(f"RPC URL not set. Use --rpc-url or set env {hint}", file=sys.stderr)
        if args.output_json_file:
            _write_json_report(
                args.output_json_file,
                check_type="owner",
                chain=chain,
                chain_label=CHAIN_DISPLAY_NAMES.get(chain, chain),
                skipped=0,
                ok=0,
                fail=1,
                failed_contracts=[],
                pending_owner_contracts=[],
                error=f"RPC URL not set. Use --rpc-url or set env {hint}",
            )
        return 2
    if not args.dry_run:
        preflight_err = rpc_preflight(rpc_url, timeout=20, chain=chain)
        if preflight_err:
            print(f"RPC preflight failed: {preflight_err}", file=sys.stderr)
            if args.output_json_file:
                _write_json_report(
                    args.output_json_file,
                    check_type="owner",
                    chain=chain,
                    chain_label=CHAIN_DISPLAY_NAMES.get(chain, chain),
                    skipped=0,
                    ok=0,
                    fail=1,
                    failed_contracts=[],
                    pending_owner_contracts=[],
                    error=f"RPC preflight failed: {preflight_err}",
                )
            return 2

    deployments = collect_deployment_addresses(repo_root, chain, components)
    if not deployments:
        print(f"No deployments found for chain={chain}, components={components}", file=sys.stderr)
        if args.output_json_file:
            _write_json_report(
                args.output_json_file,
                check_type="owner",
                chain=chain,
                chain_label=CHAIN_DISPLAY_NAMES.get(chain, chain),
                skipped=0,
                ok=0,
                fail=0,
                failed_contracts=[],
                pending_owner_contracts=[],
            )
        return 0

    deployments.sort(key=lambda x: (x[0], x[1]))  # alphabetical: component, then contract name

    has_failure = False
    skip_count = 0
    ok_count = 0
    fail_count = 0
    failed_contracts: list[tuple[str, str, str]] = []
    pending_owner_contracts: list[tuple[str, str, str, str]] = []  # (component, contract_name, address, pending_owner)

    owner_results_by_address: dict[str, tuple[str | None, str | None]] = {}
    pending_owner_by_address: dict[str, str] = {}
    if not args.dry_run:
        owner_targets: list[tuple[str, str, str]] = []
        owner_calls: list[tuple[str, str]] = []
        for component, contract_name, address, abi in deployments:
            if contract_name in CONTRACTS_EXCLUDED:
                continue
            if not abi_has_owner(abi):
                continue
            owner_targets.append((component, contract_name, address))
            owner_calls.append((address, OWNER_SELECTOR))

        if owner_calls:
            owner_results, owner_batch_err = multicall_eth_calls(chain, rpc_url, owner_calls, timeout=180)
            if owner_batch_err:
                for _component, _contract_name, address in owner_targets:
                    owner_results_by_address[address] = (None, owner_batch_err)
            else:
                for (_component, _contract_name, address), (raw_result, call_err) in zip(owner_targets, owner_results):
                    if call_err:
                        owner_results_by_address[address] = (None, call_err)
                    else:
                        owner_results_by_address[address] = _decode_owner_like_result(
                            raw_result,
                            "empty_result (possible revert, no code, or non-standard owner())",
                        )

        pending_lookup_candidates: list[tuple[str, str, str]] = []
        for component, contract_name, address, abi in deployments:
            if contract_name in CONTRACTS_EXCLUDED or not abi_has_owner(abi):
                continue
            owner, owner_err = owner_results_by_address.get(address, (None, "missing_owner_result"))
            if owner is None or owner in dao_addresses:
                continue
            pending_lookup_candidates.append((component, contract_name, address))

        if pending_lookup_candidates:
            pending_calls = [(address, PENDING_OWNER_SELECTOR) for _component, _contract_name, address in pending_lookup_candidates]
            pending_results, pending_batch_err = multicall_eth_calls(chain, rpc_url, pending_calls, timeout=180)
            if pending_batch_err:
                pending_results = [(None, pending_batch_err)] * len(pending_lookup_candidates)
            for (_component, _contract_name, address), (raw_result, call_err) in zip(
                pending_lookup_candidates, pending_results
            ):
                if call_err:
                    continue
                pending_owner, _pending_err = _decode_owner_like_result(
                    raw_result,
                    "empty_result (possible revert, no code, or non-standard pendingOwner())",
                )
                if pending_owner:
                    pending_owner_by_address[address] = pending_owner

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

        owner, owner_err = owner_results_by_address.get(address, (None, "missing_owner_result"))
        if owner is None:
            is_silo_hook = contract_name.startswith("SiloHook")
            if owner_err == "owner_is_zero_address" and is_silo_hook:
                is_proxy, proxy_details = detect_proxy_info(chain, rpc_url, address)
                if not is_proxy:
                    print(
                        f"[ ok ] {component} {contract_name} owner is zero (allowed for non-proxy SiloHook implementation)"
                    )
                    print(f"       -> proxy_check: {proxy_details}")
                    ok_count += 1
                    continue
                print(
                    f"[FAIL] {component} {contract_name} owner() call failed for {address} "
                    f"(ABI has owner(); reason: owner_is_zero_address; proxy_check: proxy; {proxy_details})"
                )
            else:
                print(
                    f"[FAIL] {component} {contract_name} owner() call failed for {address} "
                    f"(ABI has owner(); reason: {owner_err or 'unknown'})"
                )
            has_failure = True
            fail_count += 1
            failed_contracts.append((component, contract_name, address))
            continue

        if owner in dao_addresses:
            print(f"[ ok ] {component} {contract_name} owner is DAO (current or legacy)")
            ok_count += 1
            continue

        key = addr_to_key.get(owner)
        if key is None:
            print(
                f"[FAIL] {component} {contract_name} owner {owner} not in common/addresses/{chain}.json "
                "(expected DAO or DAO_OLD)"
            )
        else:
            print(f"[FAIL] {component} {contract_name} owner is {key} ({owner}), expected DAO or DAO_OLD")
        pending = pending_owner_by_address.get(address)
        if pending:
            pending_key = addr_to_key.get(pending)
            if pending_key is not None:
                print(f"       -> pending owner: {pending_key}")
            else:
                print(f"       -> pending owner: unknown ({pending})")
            pending_owner_contracts.append((component, contract_name, address, pending))
        has_failure = True
        fail_count += 1
        failed_contracts.append((component, contract_name, address))

    if args.dry_run:
        print(f"Dry-run: would check {len(deployments)} deployments for chain={chain}.")
        if args.output_json_file:
            _write_json_report(
                args.output_json_file,
                check_type="owner",
                chain=chain,
                chain_label=CHAIN_DISPLAY_NAMES.get(chain, chain),
                skipped=skip_count,
                ok=ok_count,
                fail=fail_count,
                failed_contracts=failed_contracts,
                pending_owner_contracts=pending_owner_contracts,
            )
        return 0

    print()
    print(f"Summary: skipped={skip_count} ok={ok_count} fail={fail_count}")
    print()

    chain_label = CHAIN_DISPLAY_NAMES.get(chain, chain)

    if failed_contracts:
        print()
        print(f"Contracts failing verification on {chain_label}:")
        for component, contract_name, contract_address in failed_contracts:
            print(f"  - {component}/{contract_name} {contract_address}")

    if pending_owner_contracts:
        print()
        print(f"Contracts with pending owner to accept on {chain_label}:")
        for component, contract_name, address, pending_owner in pending_owner_contracts:
            print(f"  - {component}/{contract_name} {address} (pending owner: {pending_owner})")
        print()
        print(f"Acceptance ownership method signature: acceptOwnership() {ACCEPT_OWNERSHIP_SELECTOR}")
        print()

    if args.output_json_file:
        _write_json_report(
            args.output_json_file,
            check_type="owner",
            chain=chain,
            chain_label=chain_label,
            skipped=skip_count,
            ok=ok_count,
            fail=fail_count,
            failed_contracts=failed_contracts,
            pending_owner_contracts=pending_owner_contracts,
        )

    return 1 if has_failure and not args.no_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
