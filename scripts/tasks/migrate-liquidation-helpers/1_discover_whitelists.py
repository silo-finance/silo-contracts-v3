#!/usr/bin/env python3
"""
Discover hook/controller liquidation whitelists for markets in _siloDeployments.json.

Per chain (RPC_<CHAIN>):
  - resolve NEW/OLD helpers from deployments + git file history
  - probe ALLOWED_ROLE on hooks AND controllers (not mutually exclusive; both can apply)
  - fetch VERSION() for hooks/controllers
  - totalAssets as human-readable numbers (via asset + decimals)
  - emit inventory_<chain>.json + warnings for public/empty markets

Usage:
  python3 scripts/tasks/migrate-liquidation-helpers/1_discover_whitelists.py --chain mainnet
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = Path(__file__).resolve().parents[3]
REPO_SCRIPTS_DIR = REPO_ROOT / "scripts"
if str(REPO_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(REPO_SCRIPTS_DIR))
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from rpc_multicall import multicall_eth_calls, resolve_primary_rpc_url, rpc_preflight  # noqa: E402

from helpers_from_deployments import (  # noqa: E402
    collect_new_addresses,
    collect_old_addresses,
    is_address,
    normalize_address,
    pairs_to_json,
    resolve_helpers_for_chain,
)

SILO_DEPLOYMENTS_JSON = REPO_ROOT / "silo-core" / "deploy" / "silo" / "_siloDeployments.json"
DEFAULT_OUT_DIR = SCRIPT_DIR / "out"

ALLOWED_ROLE = "0xd5dc6b389d0dd5687ab5bd9338f760ebeaff2d2852a93a9a9ebaebbfefc763ac"

GET_SILOS_SELECTOR = "0xaecc90cb"
GET_SHARE_TOKENS_SELECTOR = "0x483b24f0"
GET_CONFIG_SELECTOR = "0xe48a5f7b"
ALLOWED_ROLE_SELECTOR = "0xd32f7154"
GET_ROLE_MEMBERS_SELECTOR = "0xa3246ad3"  # getRoleMembers(bytes32) -> address[]
GET_ROLE_MEMBER_COUNT_SELECTOR = "0xca15c873"  # fallback
GET_ROLE_MEMBER_SELECTOR = "0x9010d07c"  # fallback
OWNER_SELECTOR = "0x8da5cb5b"
CONFIGURED_GAUGES_SELECTOR = "0xa37d9411"
TOTAL_ASSETS_SELECTOR = "0x01e1d114"
VERSION_SELECTOR = "0xffa1ad74"
ASSET_SELECTOR = "0x38d52e0f"
DECIMALS_SELECTOR = "0x313ce567"

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

CHAIN_RPC_ENV_CANDIDATES: dict[str, list[str]] = {
    "arbitrum_one": ["RPC_ARBITRUM_ONE", "RPC_ARBITRUM"],
    "avalanche": ["RPC_AVALANCHE"],
    "base": ["RPC_BASE"],
    "bnb": ["RPC_BNB"],
    "injective": ["RPC_INJECTIVE"],
    "ink": ["RPC_INK"],
    "mainnet": ["RPC_MAINNET"],
    "mantle": ["RPC_MANTLE"],
    "megaeth": ["RPC_MEGAETH"],
    "okx": ["RPC_OKX"],
    "optimism": ["RPC_OPTIMISM"],
    "sonic": ["RPC_SONIC"],
    "xdc": ["RPC_XDC"],
}

MULTICALL_CHUNK = 80


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Discover liquidation whitelist targets per chain.")
    parser.add_argument("--chain", required=True, help="Chain alias (e.g. mainnet, arbitrum_one).")
    parser.add_argument(
        "--silo-deployments",
        type=Path,
        default=SILO_DEPLOYMENTS_JSON,
        help=f"Path to _siloDeployments.json (default: {SILO_DEPLOYMENTS_JSON})",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUT_DIR})",
    )
    parser.add_argument(
        "--rpc-url",
        default="",
        help="Optional explicit RPC URL (otherwise RPC_<CHAIN> env).",
    )
    parser.add_argument(
        "--old-ref",
        default="",
        help="Optional git ref override for OLD helper addresses.",
    )
    return parser.parse_args()


def rpc_url_for_chain(chain: str, explicit: str) -> str | None:
    if explicit.strip():
        return explicit.strip()
    for env_name in CHAIN_RPC_ENV_CANDIDATES.get(chain, []):
        value = (os.environ.get(env_name) or "").strip()
        if value:
            return value
    return resolve_primary_rpc_url(chain, None)


def load_markets_for_chain(path: Path, chain: str) -> list[dict[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("silo deployments root must be an object")
    chain_map = data.get(chain)
    if not isinstance(chain_map, dict):
        return []
    markets: list[dict[str, str]] = []
    for name, addr in sorted(chain_map.items(), key=lambda x: x[0]):
        if not isinstance(name, str) or not isinstance(addr, str):
            continue
        if not is_address(addr):
            continue
        markets.append({"marketName": name, "siloConfig": normalize_address(addr)})
    return markets


def encode_address_arg(addr: str) -> str:
    return "0" * 24 + normalize_address(addr)[2:]


def encode_bytes32_arg(value: str) -> str:
    h = value[2:] if value.startswith("0x") else value
    return h.lower().zfill(64)


def encode_uint_arg(value: int) -> str:
    return hex(value)[2:].zfill(64)


def decode_address(hex_result: str | None) -> str | None:
    if not isinstance(hex_result, str) or not hex_result or hex_result == "0x":
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < 64:
        return None
    candidate = "0x" + data[-40:]
    if not is_address(candidate):
        return None
    return normalize_address(candidate)


def decode_addresses(hex_result: str | None, count: int) -> list[str] | None:
    if not isinstance(hex_result, str) or not hex_result:
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < count * 64:
        return None
    out: list[str] = []
    for i in range(count):
        chunk = data[i * 64 : (i + 1) * 64]
        candidate = "0x" + chunk[-40:]
        if not is_address(candidate):
            return None
        out.append(normalize_address(candidate))
    return out


def decode_address_array(hex_result: str | None) -> list[str] | None:
    """Decode ABI-encoded address[] (dynamic)."""
    if not isinstance(hex_result, str) or not hex_result:
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < 128:
        return None
    try:
        offset = int(data[0:64], 16) * 2
        if offset + 64 > len(data):
            return None
        length = int(data[offset : offset + 64], 16)
        start = offset + 64
        end = start + length * 64
        if end > len(data):
            return None
        out: list[str] = []
        for i in range(length):
            chunk = data[start + i * 64 : start + (i + 1) * 64]
            candidate = "0x" + chunk[-40:]
            if not is_address(candidate):
                return None
            out.append(normalize_address(candidate))
        return out
    except ValueError:
        return None


def decode_uint(hex_result: str | None) -> int | None:
    if not isinstance(hex_result, str) or not hex_result or hex_result == "0x":
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    try:
        return int(data, 16)
    except ValueError:
        return None


def decode_abi_string(hex_result: str | None) -> str | None:
    if not isinstance(hex_result, str) or not hex_result:
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < 128:
        return None
    try:
        offset = int(data[0:64], 16) * 2
        if offset + 64 > len(data):
            return None
        length = int(data[offset : offset + 64], 16)
        start = offset + 64
        end = start + (length * 2)
        if end > len(data):
            return None
        return bytes.fromhex(data[start:end]).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None


def assets_to_number(raw: int | None, decimals: int | None) -> float | None:
    if raw is None or decimals is None:
        return None
    if decimals < 0 or decimals > 77:
        return None
    return raw / (10**decimals)


def decode_hook_from_config(hex_result: str | None) -> str | None:
    """ConfigData.hookReceiver is word index 15 (16th field)."""
    if not isinstance(hex_result, str) or not hex_result:
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    # 17 words minimum (incl bool)
    if len(data) < 17 * 64:
        return None
    chunk = data[15 * 64 : 16 * 64]
    candidate = "0x" + chunk[-40:]
    if not is_address(candidate):
        return None
    return normalize_address(candidate)


def multicall_chunked(
    chain: str, rpc_url: str, calls: list[tuple[str, str]]
) -> list[tuple[str | None, str | None]]:
    if not calls:
        return []
    results: list[tuple[str | None, str | None]] = []
    for i in range(0, len(calls), MULTICALL_CHUNK):
        chunk = calls[i : i + MULTICALL_CHUNK]
        chunk_results, err = multicall_eth_calls(chain, rpc_url, chunk, timeout=120)
        if err:
            raise RuntimeError(f"multicall failed: {err}")
        results.extend(chunk_results)
    return results


def probe_allowed_role_support(
    chain: str, rpc_url: str, addresses: list[str]
) -> dict[str, bool]:
    unique = sorted(set(addresses), key=str.lower)
    if not unique:
        return {}
    calls = [(addr, ALLOWED_ROLE_SELECTOR) for addr in unique]
    results = multicall_chunked(chain, rpc_url, calls)
    out: dict[str, bool] = {}
    for addr, (value, err) in zip(unique, results):
        out[addr] = err is None and value is not None and value != "0x"
    return out


def fetch_owners(chain: str, rpc_url: str, addresses: list[str]) -> dict[str, str | None]:
    unique = sorted(set(addresses), key=str.lower)
    if not unique:
        return {}
    calls = [(addr, OWNER_SELECTOR) for addr in unique]
    results = multicall_chunked(chain, rpc_url, calls)
    out: dict[str, str | None] = {}
    for addr, (value, err) in zip(unique, results):
        out[addr] = None if err else decode_address(value)
    return out


def _fetch_members_fallback(chain: str, rpc_url: str, target: str) -> list[str] | None:
    """Fallback when getRoleMembers is unavailable: count + getRoleMember(i)."""
    count_data = GET_ROLE_MEMBER_COUNT_SELECTOR + encode_bytes32_arg(ALLOWED_ROLE)
    count_results = multicall_chunked(chain, rpc_url, [(target, count_data)])
    if not count_results:
        return None
    value, err = count_results[0]
    if err:
        return None
    count = decode_uint(value)
    if count is None:
        return None
    if count == 0:
        return []

    calls: list[tuple[str, str]] = []
    for i in range(count):
        data = (
            GET_ROLE_MEMBER_SELECTOR
            + encode_bytes32_arg(ALLOWED_ROLE)
            + encode_uint_arg(i)
        )
        calls.append((target, data))
    results = multicall_chunked(chain, rpc_url, calls)
    members: list[str] = []
    for res_value, res_err in results:
        if res_err:
            continue
        addr = decode_address(res_value)
        if addr:
            members.append(addr)
    return members


def fetch_role_members(
    chain: str, rpc_url: str, addresses: list[str]
) -> dict[str, list[str] | None]:
    """
    One getRoleMembers(ALLOWED_ROLE) call per target (via multicall).
    Returns address -> members list, or None if the call failed.
    """
    unique = sorted(set(addresses), key=str.lower)
    if not unique:
        return {}

    data = GET_ROLE_MEMBERS_SELECTOR + encode_bytes32_arg(ALLOWED_ROLE)
    calls = [(addr, data) for addr in unique]
    results = multicall_chunked(chain, rpc_url, calls)

    out: dict[str, list[str] | None] = {}
    for addr, (value, err) in zip(unique, results):
        if err is None:
            decoded = decode_address_array(value)
            if decoded is not None:
                out[addr] = decoded
                continue
        # Fallback for older enumerable implementations without getRoleMembers.
        print(f"[warn] {addr}: getRoleMembers failed, falling back to getRoleMember loop")
        out[addr] = _fetch_members_fallback(chain, rpc_url, addr)
    return out


def fetch_versions(chain: str, rpc_url: str, addresses: list[str]) -> dict[str, str | None]:
    unique = sorted(set(addresses), key=str.lower)
    if not unique:
        return {}
    calls = [(addr, VERSION_SELECTOR) for addr in unique]
    results = multicall_chunked(chain, rpc_url, calls)
    out: dict[str, str | None] = {}
    for addr, (value, err) in zip(unique, results):
        out[addr] = None if err else decode_abi_string(value)
    return out


def fetch_total_assets(chain: str, rpc_url: str, silos: list[str]) -> dict[str, int | None]:
    unique = sorted(set(silos), key=str.lower)
    if not unique:
        return {}
    calls = [(addr, TOTAL_ASSETS_SELECTOR) for addr in unique]
    results = multicall_chunked(chain, rpc_url, calls)
    out: dict[str, int | None] = {}
    for addr, (value, err) in zip(unique, results):
        out[addr] = None if err else decode_uint(value)
    return out


def fetch_silo_asset_decimals(
    chain: str, rpc_url: str, silos: list[str]
) -> dict[str, tuple[str | None, int | None]]:
    """Return silo -> (underlying asset, decimals)."""
    unique = sorted(set(silos), key=str.lower)
    if not unique:
        return {}

    asset_calls = [(addr, ASSET_SELECTOR) for addr in unique]
    asset_results = multicall_chunked(chain, rpc_url, asset_calls)

    assets: dict[str, str | None] = {}
    asset_addrs: list[str] = []
    for silo, (value, err) in zip(unique, asset_results):
        asset = None if err else decode_address(value)
        assets[silo] = asset
        if asset:
            asset_addrs.append(asset)

    decimals_by_asset: dict[str, int | None] = {}
    unique_assets = sorted(set(asset_addrs), key=str.lower)
    if unique_assets:
        dec_calls = [(addr, DECIMALS_SELECTOR) for addr in unique_assets]
        dec_results = multicall_chunked(chain, rpc_url, dec_calls)
        for asset, (value, err) in zip(unique_assets, dec_results):
            decimals_by_asset[asset] = None if err else decode_uint(value)

    out: dict[str, tuple[str | None, int | None]] = {}
    for silo in unique:
        asset = assets.get(silo)
        decimals = decimals_by_asset.get(asset) if asset else None
        out[silo] = (asset, decimals)
    return out


def main() -> int:
    args = parse_args()
    chain = args.chain.strip().lower()
    if chain not in CHAIN_IDS:
        print(f"[FAIL] unknown chain alias: {chain}")
        return 1

    rpc_url = rpc_url_for_chain(chain, args.rpc_url)
    if not rpc_url:
        print(f"[FAIL] no RPC URL for {chain} (set RPC_* or --rpc-url)")
        return 1

    preflight_err = rpc_preflight(rpc_url, chain=chain)
    if preflight_err:
        print(f"[FAIL] rpc preflight failed: {preflight_err}")
        return 1

    markets = load_markets_for_chain(args.silo_deployments, chain)
    if not markets:
        print(f"[warn] {chain}: no markets in {args.silo_deployments}")
        return 0

    old_ref = args.old_ref.strip() or None
    helper_pairs = resolve_helpers_for_chain(chain, old_ref=old_ref)
    new_helpers = collect_new_addresses(helper_pairs)
    old_helpers = collect_old_addresses(helper_pairs)

    print(f"[info] {chain}: markets={len(markets)} helpers_new={len(new_helpers)} helpers_old={len(old_helpers)}")
    for pair in helper_pairs:
        print(f"  helper {pair.file_name}: new={pair.new_address} old={pair.old_address or '-'}")

    # Phase 1: getSilos
    silos_calls = [(m["siloConfig"], GET_SILOS_SELECTOR) for m in markets]
    silos_results = multicall_chunked(chain, rpc_url, silos_calls)

    market_rows: list[dict[str, Any]] = []
    for market, (value, err) in zip(markets, silos_results):
        row: dict[str, Any] = {
            "marketName": market["marketName"],
            "siloConfig": market["siloConfig"],
            "warnings": [],
        }
        if err:
            row["warnings"].append(f"getSilos_failed:{err}")
            row["skip"] = True
            market_rows.append(row)
            print(f"[warn] {market['marketName']}: getSilos failed ({err})")
            continue
        decoded = decode_addresses(value, 2)
        if not decoded:
            row["warnings"].append("getSilos_decode_failed")
            row["skip"] = True
            market_rows.append(row)
            print(f"[warn] {market['marketName']}: getSilos decode failed")
            continue
        row["silo0"], row["silo1"] = decoded
        row["skip"] = False
        market_rows.append(row)

    active = [r for r in market_rows if not r.get("skip")]

    # Phase 2: getShareTokens + getConfig(silo0) for hook
    share_calls: list[tuple[str, str]] = []
    config_calls: list[tuple[str, str]] = []
    for row in active:
        for silo_key in ("silo0", "silo1"):
            silo = row[silo_key]
            share_calls.append(
                (row["siloConfig"], GET_SHARE_TOKENS_SELECTOR + encode_address_arg(silo))
            )
        config_calls.append(
            (row["siloConfig"], GET_CONFIG_SELECTOR + encode_address_arg(row["silo0"]))
        )

    share_results = multicall_chunked(chain, rpc_url, share_calls)
    config_results = multicall_chunked(chain, rpc_url, config_calls)

    for idx, row in enumerate(active):
        s0 = share_results[idx * 2]
        s1 = share_results[idx * 2 + 1]
        cfg = config_results[idx]

        for silo_key, result, label in (
            ("silo0", s0, "shareTokens0"),
            ("silo1", s1, "shareTokens1"),
        ):
            value, err = result
            if err:
                row["warnings"].append(f"{label}_failed:{err}")
                row["skip"] = True
                print(f"[warn] {row['marketName']}: {label} failed ({err})")
                continue
            decoded = decode_addresses(value, 3)
            if not decoded:
                row["warnings"].append(f"{label}_decode_failed")
                row["skip"] = True
                print(f"[warn] {row['marketName']}: {label} decode failed")
                continue
            protected, collateral, _debt = decoded
            row[f"{silo_key}Protected"] = protected
            row[f"{silo_key}Collateral"] = collateral

        cfg_value, cfg_err = cfg
        if cfg_err:
            row["warnings"].append(f"getConfig_failed:{cfg_err}")
            row["skip"] = True
            print(f"[warn] {row['marketName']}: getConfig failed ({cfg_err})")
            continue
        hook = decode_hook_from_config(cfg_value)
        if not hook:
            row["warnings"].append("hook_decode_failed")
            row["skip"] = True
            print(f"[warn] {row['marketName']}: hook decode failed")
            continue
        row["hook"] = hook

    active = [r for r in active if not r.get("skip")]

    # Phase 3: probe hook whitelist support
    hooks = [r["hook"] for r in active]
    hook_has_whitelist = probe_allowed_role_support(chain, rpc_url, hooks)

    # Phase 4: configuredGauges for collateral/protected on both silos
    gauge_calls: list[tuple[str, str]] = []
    gauge_meta: list[tuple[dict[str, Any], str]] = []
    for row in active:
        hook = row["hook"]
        for key in (
            "silo0Protected",
            "silo0Collateral",
            "silo1Protected",
            "silo1Collateral",
        ):
            share = row.get(key)
            if not share:
                continue
            gauge_calls.append((hook, CONFIGURED_GAUGES_SELECTOR + encode_address_arg(share)))
            gauge_meta.append((row, key))

    gauge_results = multicall_chunked(chain, rpc_url, gauge_calls)
    controllers_by_market: dict[str, set[str]] = {}
    all_controllers: set[str] = set()
    for (row, _key), (value, err) in zip(gauge_meta, gauge_results):
        if err:
            continue
        ctrl = decode_address(value)
        if not ctrl or ctrl == "0x0000000000000000000000000000000000000000":
            continue
        controllers_by_market.setdefault(row["siloConfig"], set()).add(ctrl)
        all_controllers.add(ctrl)

    controller_has_whitelist = probe_allowed_role_support(chain, rpc_url, sorted(all_controllers))

    # VERSION() for every hook and every whitelist-capable controller (multicall is cheap).
    version_addrs = sorted(set(hooks) | {c for c, ok in controller_has_whitelist.items() if ok}, key=str.lower)
    versions = fetch_versions(chain, rpc_url, version_addrs)

    # Collect whitelist-capable targets on hook AND/OR controllers (both can apply on one market).
    targets: dict[str, dict[str, Any]] = {}
    for row in active:
        hook = row["hook"]
        if hook_has_whitelist.get(hook):
            targets.setdefault(
                hook,
                {
                    "target": hook,
                    "targetType": "hook",
                    "markets": [],
                },
            )
            targets[hook]["markets"].append(row["marketName"])

        for ctrl in sorted(controllers_by_market.get(row["siloConfig"], set())):
            if not controller_has_whitelist.get(ctrl):
                continue
            targets.setdefault(
                ctrl,
                {
                    "target": ctrl,
                    "targetType": "controller",
                    "markets": [],
                },
            )
            targets[ctrl]["markets"].append(row["marketName"])

    target_addrs = sorted(targets.keys(), key=str.lower)
    owners = fetch_owners(chain, rpc_url, target_addrs)
    members_by_target = fetch_role_members(chain, rpc_url, target_addrs)

    target_records: list[dict[str, Any]] = []
    for addr in target_addrs:
        members = members_by_target.get(addr)
        if members is None:
            print(f"[warn] target {addr}: failed to fetch ALLOWED_ROLE members")
            continue
        admin = owners.get(addr)
        rec = {
            "target": addr,
            "targetType": targets[addr]["targetType"],
            "version": versions.get(addr),
            "admin": admin,
            "members": members,
            "markets": sorted(set(targets[addr]["markets"])),
        }
        target_records.append(rec)

    # Build market inventory + warnings
    inventory_markets: list[dict[str, Any]] = []
    warnings_out: list[str] = []

    silos_for_assets: list[str] = []
    for row in active:
        silos_for_assets.extend([row["silo0"], row["silo1"]])
    total_assets_raw = fetch_total_assets(chain, rpc_url, silos_for_assets)
    asset_decimals = fetch_silo_asset_decimals(chain, rpc_url, silos_for_assets)

    for row in market_rows:
        if row.get("skip"):
            for w in row.get("warnings", []):
                warnings_out.append(f"{row['marketName']}: {w}")
            continue

        hook = row["hook"]
        market_controller_addrs = sorted(
            [
                c
                for c in controllers_by_market.get(row["siloConfig"], set())
                if controller_has_whitelist.get(c)
            ],
            key=str.lower,
        )
        market_controllers = [
            {"address": c, "version": versions.get(c)} for c in market_controller_addrs
        ]
        hook_wl = bool(hook_has_whitelist.get(hook))
        has_any_wl = hook_wl or bool(market_controller_addrs)

        ta0 = assets_to_number(
            total_assets_raw.get(row["silo0"]),
            asset_decimals.get(row["silo0"], (None, None))[1],
        )
        ta1 = assets_to_number(
            total_assets_raw.get(row["silo1"]),
            asset_decimals.get(row["silo1"], (None, None))[1],
        )
        assets_sum = (ta0 or 0.0) + (ta1 or 0.0)

        market_warnings: list[str] = list(row.get("warnings", []))

        if not has_any_wl:
            msg = (
                f"public_market: no whitelist on hook or controller "
                f"(hook={hook}, totalAssets~={assets_sum})"
            )
            market_warnings.append(msg)
            warnings_out.append(f"{row['marketName']}: {msg}")
            print(f"[warn] {row['marketName']}: {msg}")
        else:
            if hook_wl:
                hook_members = members_by_target.get(hook) or []
                if len(hook_members) == 0 and assets_sum > 0:
                    msg = f"empty_hook_whitelist_with_assets totalAssets~={assets_sum}"
                    market_warnings.append(msg)
                    warnings_out.append(f"{row['marketName']}: {msg}")
                    print(f"[warn] {row['marketName']}: {msg}")
            for ctrl in market_controller_addrs:
                ctrl_members = members_by_target.get(ctrl) or []
                if len(ctrl_members) == 0 and assets_sum > 0:
                    msg = (
                        f"empty_controller_whitelist_with_assets "
                        f"controller={ctrl} totalAssets~={assets_sum}"
                    )
                    market_warnings.append(msg)
                    warnings_out.append(f"{row['marketName']}: {msg}")
                    print(f"[warn] {row['marketName']}: {msg}")

        inventory_markets.append(
            {
                "marketName": row["marketName"],
                "siloConfig": row["siloConfig"],
                "silo0": row["silo0"],
                "silo1": row["silo1"],
                "hook": hook,
                "hookVersion": versions.get(hook),
                "hookHasWhitelist": hook_wl,
                "controllers": market_controllers,
                "totalAssetsSilo0": ta0,
                "totalAssetsSilo1": ta1,
                "warnings": market_warnings,
            }
        )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.output_dir / f"inventory_{chain}.json"
    payload = {
        "chain": chain,
        "chainId": CHAIN_IDS[chain],
        "helpers": pairs_to_json(helper_pairs),
        "markets": inventory_markets,
        "targets": target_records,
    }
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    non_empty = sum(1 for t in target_records if t.get("members"))
    print(
        f"[ok] {chain}: markets={len(inventory_markets)} targets={len(target_records)} "
        f"non_empty_whitelists={non_empty} warnings={len(warnings_out)} -> {out_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
