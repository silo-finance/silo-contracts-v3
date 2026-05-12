#!/usr/bin/env python3
"""
Enrich markets JSON with hook metadata:
- hook
- hookOwner
- hookVersion

Input format:
{
  "<chain>": [
    {
      "address": "0x... (SiloConfig)",
      "id": 3001,
      "asset0": "...",
      "asset1": "..."
    }
  ]
}
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

SCRIPTS_DIR = Path(__file__).resolve().parents[2]
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.append(str(SCRIPTS_DIR))

from rpc_multicall import format_rpc_error, multicall_eth_calls, rpc_preflight, rpc_request


GET_SILOS_SELECTOR = "0xaecc90cb"
GET_SHARE_TOKENS_SELECTOR = "0x483b24f0"
HOOK_RECEIVER_SELECTOR = "0x8fea8062"
OWNER_SELECTOR = "0x8da5cb5b"
GET_VERSIONS_SELECTOR = "0xf58e82b5"

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
ADDR_RE = re.compile(r"0x[a-fA-F0-9]{40}")

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


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
        return value[1:-1]
    return value


def load_repo_env(override_existing: bool = False) -> Path | None:
    candidates = [REPO_ROOT / "env", REPO_ROOT / ".env"]
    env_path = next((p for p in candidates if p.exists() and p.is_file()), None)
    if env_path is None:
        return None

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        value = _strip_quotes(value)
        if override_existing or key not in os.environ:
            os.environ[key] = value
    return env_path


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Add hook/hookOwner/hookVersion to markets JSON.")
    parser.add_argument(
        "--input",
        default=str(script_dir / "v3_markets_by_chain.json"),
        help="Input markets JSON path.",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Output path. If empty, input file is updated in place.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Refresh hook fields even if already present.",
    )
    return parser.parse_args()


def normalize_address(address: str) -> str:
    value = address.strip()
    if not ADDR_RE.fullmatch(value):
        raise ValueError(f"Invalid address: {address}")
    return value


def get_rpc_url(chain: str) -> str | None:
    for env_name in CHAIN_RPC_ENV_CANDIDATES.get(chain, []):
        value = os.environ.get(env_name, "").strip()
        if value:
            return value
    return None


def enc_address_arg(address: str) -> str:
    addr = address[2:] if address.startswith("0x") else address
    return addr.lower().zfill(64)


def decode_abi_address_word(result_hex: str) -> str | None:
    h = result_hex[2:] if result_hex.startswith("0x") else result_hex
    if len(h) < 64:
        return None
    return "0x" + h[24:64]


def decode_get_silos(result_hex: str) -> tuple[str, str] | None:
    h = result_hex[2:] if result_hex.startswith("0x") else result_hex
    if len(h) < 128:
        return None
    silo0 = "0x" + h[24:64]
    silo1 = "0x" + h[88:128]
    return silo0, silo1


def decode_get_share_tokens(result_hex: str) -> tuple[str, str, str] | None:
    h = result_hex[2:] if result_hex.startswith("0x") else result_hex
    if len(h) < 192:
        return None
    protected_share = "0x" + h[24:64]
    collateral_share = "0x" + h[88:128]
    debt_share = "0x" + h[152:192]
    return protected_share, collateral_share, debt_share


def _abi_decode_string_at(hex_data: str, byte_offset: int) -> str | None:
    start = byte_offset * 2
    if start + 64 > len(hex_data):
        return None
    try:
        string_len = int(hex_data[start : start + 64], 16)
        data_start = start + 64
        data_end = data_start + string_len * 2
        if data_end > len(hex_data):
            return None
        raw = bytes.fromhex(hex_data[data_start:data_end])
        text = raw.decode("utf-8", errors="strict").strip()
        return text or None
    except (ValueError, UnicodeDecodeError):
        return None


def decode_abi_string_array(result_hex: str) -> list[str | None]:
    if not result_hex or not result_hex.strip():
        return []
    hex_result = result_hex.strip()
    if hex_result.startswith("0x"):
        hex_result = hex_result[2:]
    if len(hex_result) < 128:
        return []
    try:
        array_offset = int(hex_result[0:64], 16)
        base = array_offset * 2
        length = int(hex_result[base : base + 64], 16)
    except ValueError:
        return []

    out: list[str | None] = []
    for i in range(length):
        elem_offset_pos = base + 64 + i * 64
        if elem_offset_pos + 64 > len(hex_result):
            out.append(None)
            continue
        try:
            elem_offset = int(hex_result[elem_offset_pos : elem_offset_pos + 64], 16)
        except ValueError:
            out.append(None)
            continue
        elem_abs_offset = array_offset + 32 + elem_offset
        out.append(_abi_decode_string_at(hex_result, elem_abs_offset))
    return out


def encode_address_array(addresses: list[str]) -> str:
    n = len(addresses)
    offset_hex = "0" * 62 + "20"
    length_hex = hex(n)[2:].zfill(64)
    parts = [offset_hex, length_hex]
    for address in addresses:
        parts.append(address.lower().replace("0x", "").zfill(64))
    return "".join(parts)


def get_silo_lens_address(chain: str) -> str | None:
    lens_path = REPO_ROOT / "silo-core" / "deployments" / chain / "SiloLens.sol.json"
    if not lens_path.exists():
        return None
    try:
        data = json.loads(lens_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    address = data.get("address")
    if not isinstance(address, str):
        return None
    try:
        return normalize_address(address)
    except ValueError:
        return None


def get_versions_via_silo_lens(
    rpc_url: str, lens_address: str, hooks: list[str]
) -> tuple[dict[str, str], str | None]:
    if not hooks:
        return {}, None
    call_data = GET_VERSIONS_SELECTOR + encode_address_array(hooks)
    body, req_err = rpc_request(
        rpc_url,
        "eth_call",
        [{"to": lens_address, "data": call_data}, "latest"],
        timeout=90,
    )
    if req_err:
        return {}, req_err
    if body is None:
        return {}, "empty_response"
    if body.get("error"):
        return {}, f"rpc_error {format_rpc_error(body['error'])}"

    raw = (body.get("result") or "").strip()
    decoded = decode_abi_string_array(raw)
    if len(decoded) != len(hooks):
        return {}, f"decode_mismatch expected={len(hooks)} got={len(decoded)}"

    versions: dict[str, str] = {}
    for hook, version in zip(hooks, decoded):
        # SiloLens.getVersion returns "legacy" when VERSION() is missing/reverted.
        versions[hook.lower()] = version if version else "legacy"
    return versions, None


def load_markets(path: Path) -> dict[str, list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Input JSON root must be an object.")

    out: dict[str, list[dict[str, Any]]] = {}
    for chain, markets in data.items():
        if not isinstance(chain, str) or not isinstance(markets, list):
            continue
        normalized_markets: list[dict[str, Any]] = []
        for market in markets:
            if not isinstance(market, dict):
                continue
            address = market.get("address")
            if not isinstance(address, str):
                continue
            try:
                market["address"] = normalize_address(address)
            except ValueError:
                continue
            normalized_markets.append(market)
        out[chain] = normalized_markets
    return out


def should_update_market(market: dict[str, Any], force: bool) -> bool:
    if force:
        return True
    if not market.get("hook"):
        return True
    if not market.get("hookOwner"):
        return True
    if not market.get("hookVersion"):
        return True
    return False


def enrich_chain(chain: str, markets: list[dict[str, Any]], rpc_url: str, force: bool) -> tuple[int, int]:
    to_update = [m for m in markets if should_update_market(m, force)]
    if not to_update:
        return 0, 0

    preflight_err = rpc_preflight(rpc_url, timeout=20)
    if preflight_err:
        print(f"[warn] {chain}: RPC preflight failed: {preflight_err}")
        return 0, len(to_update)

    # Resolve already cached hooks from JSON first.
    config_to_hook: dict[str, str] = {}
    for market in to_update:
        hook_value = market.get("hook")
        if isinstance(hook_value, str) and ADDR_RE.fullmatch(hook_value):
            config_to_hook[market["address"].lower()] = hook_value

    # Resolve missing hook addresses only.
    need_hook_resolution = [m for m in to_update if force or m["address"].lower() not in config_to_hook]
    config_to_share_token: dict[str, str] = {}
    share_to_hook: dict[str, str] = {}

    if need_hook_resolution:
        # 1) config -> silo0 via getSilos()
        get_silos_calls = [(m["address"], GET_SILOS_SELECTOR) for m in need_hook_resolution]
        get_silos_results, get_silos_err = multicall_eth_calls(chain, rpc_url, get_silos_calls, timeout=180)
        if get_silos_err:
            print(f"[warn] {chain}: getSilos multicall failed: {get_silos_err}")
            return 0, len(to_update)

        config_to_silo0: dict[str, str] = {}
        for market, (raw, call_err) in zip(need_hook_resolution, get_silos_results):
            if call_err or not raw:
                continue
            silos = decode_get_silos(raw)
            if silos is None:
                continue
            silo0, _silo1 = silos
            config_to_silo0[market["address"].lower()] = silo0

        # 2) config.getShareTokens(silo0) -> pick share token
        get_share_tokens_calls: list[tuple[str, str]] = []
        share_token_market_keys: list[str] = []
        for market in need_hook_resolution:
            config_addr = market["address"]
            silo0 = config_to_silo0.get(config_addr.lower())
            if not silo0:
                continue
            call_data = GET_SHARE_TOKENS_SELECTOR + enc_address_arg(silo0)
            get_share_tokens_calls.append((config_addr, call_data))
            share_token_market_keys.append(config_addr.lower())

        if get_share_tokens_calls:
            share_results, share_err = multicall_eth_calls(chain, rpc_url, get_share_tokens_calls, timeout=180)
            if share_err:
                print(f"[warn] {chain}: getShareTokens multicall failed: {share_err}")
            else:
                for market_key, (raw, call_err) in zip(share_token_market_keys, share_results):
                    if call_err or not raw:
                        continue
                    share_tokens = decode_get_share_tokens(raw)
                    if share_tokens is None:
                        continue
                    protected_share, collateral_share, debt_share = share_tokens
                    chosen = collateral_share
                    if chosen.lower() == ZERO_ADDRESS:
                        chosen = protected_share if protected_share.lower() != ZERO_ADDRESS else debt_share
                    if chosen.lower() != ZERO_ADDRESS:
                        config_to_share_token[market_key] = chosen

        # 3) shareToken -> hook via hookReceiver()
        unique_share_tokens = sorted(set(config_to_share_token.values()), key=str.lower)
        if unique_share_tokens:
            hook_calls = [(share, HOOK_RECEIVER_SELECTOR) for share in unique_share_tokens]
            hook_results, hook_err = multicall_eth_calls(chain, rpc_url, hook_calls, timeout=180)
            if hook_err:
                print(f"[warn] {chain}: hookReceiver multicall failed: {hook_err}")
            else:
                for share, (raw, call_err) in zip(unique_share_tokens, hook_results):
                    if call_err or not raw:
                        continue
                    hook_addr = decode_abi_address_word(raw)
                    if hook_addr and hook_addr.lower() != ZERO_ADDRESS:
                        share_to_hook[share.lower()] = hook_addr

        for config_lower, share in config_to_share_token.items():
            hook_addr = share_to_hook.get(share.lower())
            if hook_addr:
                config_to_hook[config_lower] = hook_addr

    # Resolve what we still need from hook side (field-level cache).
    hooks_need_owner: set[str] = set()
    hooks_need_version: set[str] = set()
    for market in to_update:
        hook_addr = config_to_hook.get(market["address"].lower())
        if not hook_addr:
            continue
        if force or not market.get("hookOwner"):
            hooks_need_owner.add(hook_addr)
        if force or not market.get("hookVersion"):
            hooks_need_version.add(hook_addr)

    hook_owner: dict[str, str] = {}
    hook_version: dict[str, str] = {}

    if hooks_need_owner:
        owner_calls = [(hook, OWNER_SELECTOR) for hook in sorted(hooks_need_owner, key=str.lower)]
        owner_results, owner_err = multicall_eth_calls(chain, rpc_url, owner_calls, timeout=180)
        if owner_err:
            print(f"[warn] {chain}: owner() multicall failed: {owner_err}")
        else:
            for hook, (raw, call_err) in zip([c[0] for c in owner_calls], owner_results):
                if call_err or not raw:
                    continue
                owner_addr = decode_abi_address_word(raw)
                if owner_addr and owner_addr.lower() != ZERO_ADDRESS:
                    hook_owner[hook.lower()] = owner_addr

    if hooks_need_version:
        lens_address = get_silo_lens_address(chain)
        if not lens_address:
            print(f"[warn] {chain}: missing SiloLens deployment, cannot fetch hook versions")
        else:
            hooks_for_version = sorted(hooks_need_version, key=str.lower)
            versions, versions_err = get_versions_via_silo_lens(rpc_url, lens_address, hooks_for_version)
            if versions_err:
                print(f"[warn] {chain}: SiloLens.getVersions failed: {versions_err}")
            else:
                hook_version.update(versions)

    updated = 0
    failed = 0
    for market in to_update:
        config_addr = market["address"].lower()
        share_token = config_to_share_token.get(config_addr)
        hook = share_to_hook.get(share_token.lower()) if share_token else None
        if not hook:
            hook = config_to_hook.get(config_addr)
        if not hook:
            failed += 1
            continue

        market["hook"] = hook
        if force or not market.get("hookOwner"):
            market["hookOwner"] = hook_owner.get(hook.lower())
        if force or not market.get("hookVersion"):
            market["hookVersion"] = hook_version.get(hook.lower())
        updated += 1

    return updated, failed


def main() -> int:
    args = parse_args()
    env_path = load_repo_env(override_existing=False)
    if env_path:
        print(f"[info] loaded env from {env_path}")
    input_path = Path(args.input)
    output_path = Path(args.output) if args.output else input_path

    markets_by_chain = load_markets(input_path)

    total_updated = 0
    total_failed = 0
    for chain, markets in markets_by_chain.items():
        if not markets:
            continue
        rpc_url = get_rpc_url(chain)
        if not rpc_url:
            print(f"[warn] {chain}: missing RPC env, skipping")
            continue
        updated, failed = enrich_chain(chain, markets, rpc_url, force=args.force)
        total_updated += updated
        total_failed += failed
        print(f"[info] {chain}: updated={updated} failed={failed}")

    output_path.write_text(
        json.dumps(markets_by_chain, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {output_path}")
    print(f"Summary: updated={total_updated} failed={total_failed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
