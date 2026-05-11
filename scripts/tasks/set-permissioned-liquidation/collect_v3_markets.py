#!/usr/bin/env python3
"""
Collect V3 Silo markets (SiloConfig addresses) by blockchain.

Rules:
- include only entries from deployments where market name contains `_id_<N>` and N >= 3000
- ignore entries without `_id_`
- include a predefined list of extra addresses even if they do not match `_id_`
- use existing output JSON as cache (if present)
- fetch missing IDs and market names (`asset0/asset1`) via multicall RPC

Output:
- one JSON file grouped by blockchain
- each market includes:
  - address (SiloConfig)
  - id (SILO_ID)
  - asset0
  - asset1

example usage:

python3 scripts/tasks/set-permissioned-liquidation/collect_v3_markets.py --skip-rpc
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

from rpc_multicall import multicall_eth_calls, rpc_preflight


ID_PATTERN = re.compile(r"_id_(\d+)", re.IGNORECASE)
DEFAULT_MIN_ID = 3000
GET_SILOS_SELECTOR = "0xaecc90cb"
SILO_ID_SELECTOR = "0x189e17e4"
ASSET_SELECTOR = "0x38d52e0f"
SYMBOL_SELECTOR = "0x95d89b41"


# Extra markets provided manually (address, chain display name).
EXTRA_MARKETS_RAW: list[tuple[str, str]] = [
    ("0xc88734b3D929bb9EAc81F9eada48D6D330a3F37F", "Arbitrum"),
    ("0xaE01a8BdA7799A7aE4D56CC255db56a7e7FaF7F8", "Ethereum"),
    ("0xF8D32Da4Ad9378C3754CE846BE02654e52b2C09d", "Ethereum"),
    ("0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2", "Sonic"),
    ("0xfAa8b214A896Dfd41FA0aaE07D55E6b15b59357a", "Ethereum"),
    ("0xD76D4130f5E10409D2361Bf934cf4b4d6E3531DF", "Arbitrum"),
    ("0x18B178B50F1fFd3dC7855C893a4e1Ac618F9B76A", "Ethereum"),
    ("0x74b21D458b9D5CF59f4b4E10A2E829C221670EE3", "Ethereum"),
    ("0x781cDF4235de2166d5C451280E617BC1142DfAe4", "Ethereum"),
    ("0xcd0d510eec4792a944E8dbe5da54DDD6777f02Ca", "Avalanche"),
    ("0x33fAdB3dB0A1687Cdd4a55AB0afa94c8102856A1", "Avalanche"),
]


# Map user-facing names -> keys used in deployments file.
CHAIN_ALIASES: dict[str, str] = {
    "arbitrum": "arbitrum_one",
    "arbitrum_one": "arbitrum_one",
    "ethereum": "mainnet",
    "mainnet": "mainnet",
    "avalanche": "avalanche",
    "sonic": "sonic",
    "bnb": "bnb",
    "injective": "injective",
    "ink": "ink",
    "megaeth": "megaeth",
    "optimism": "optimism",
    "xdc": "xdc",
    "okx": "okx",
    "base": "base",
    "mantle": "mantle",
}

# env candidates per chain (first existing value wins)
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


def normalize_chain_name(chain_name: str) -> str:
    key = chain_name.strip().lower()
    if key not in CHAIN_ALIASES:
        raise ValueError(f"Unsupported chain name: {chain_name}")
    return CHAIN_ALIASES[key]


def normalize_address(address: str) -> str:
    value = address.strip()
    if not re.fullmatch(r"0x[a-fA-F0-9]{40}", value):
        raise ValueError(f"Invalid address format: {address}")
    return value


def normalize_id(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return None


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


def decode_uint256(result_hex: str) -> int | None:
    h = result_hex[2:] if result_hex.startswith("0x") else result_hex
    if len(h) < 64:
        return None
    try:
        return int(h[-64:], 16)
    except ValueError:
        return None


def decode_symbol(result_hex: str) -> str | None:
    h = result_hex[2:] if result_hex.startswith("0x") else result_hex
    if len(h) < 64:
        return None

    # bytes32 symbol fallback
    if len(h) == 64:
        try:
            raw = bytes.fromhex(h).rstrip(b"\x00")
            value = raw.decode("utf-8", errors="strict").strip()
            return value or None
        except (ValueError, UnicodeDecodeError):
            return None

    # dynamic string ABI
    try:
        offset_bytes = int(h[0:64], 16)
        start = offset_bytes * 2
        if start + 64 > len(h):
            return None
        string_len = int(h[start : start + 64], 16)
        data_start = start + 64
        data_end = data_start + string_len * 2
        if data_end > len(h):
            return None
        raw = bytes.fromhex(h[data_start:data_end])
        value = raw.decode("utf-8", errors="strict").strip()
        return value or None
    except (ValueError, UnicodeDecodeError):
        return None


def get_rpc_url(chain: str) -> str | None:
    for env_name in CHAIN_RPC_ENV_CANDIDATES.get(chain, []):
        rpc_url = os.environ.get(env_name, "").strip()
        if rpc_url:
            return rpc_url
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect V3 SiloConfig addresses by blockchain."
    )
    parser.add_argument(
        "--deployments",
        default=str(REPO_ROOT / "silo-core/deploy/silo/_siloDeployments.json"),
        help="Path to silo deployments JSON.",
    )
    parser.add_argument(
        "--output",
        default=str(Path(__file__).resolve().parent / "v3_markets_by_chain.json"),
        help="Output JSON path.",
    )
    parser.add_argument(
        "--min-id",
        type=int,
        default=DEFAULT_MIN_ID,
        help="Minimum market id to include from deployments (default: 3000).",
    )
    parser.add_argument(
        "--skip-rpc",
        action="store_true",
        help="Do not fetch missing fields from RPC (cache + deployments only).",
    )
    return parser.parse_args()


def load_cache(cache_path: Path) -> dict[str, dict[str, dict[str, Any]]]:
    if not cache_path.exists():
        return {}
    raw = json.loads(cache_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        return {}

    cache: dict[str, dict[str, dict[str, Any]]] = {}
    for chain, items in raw.items():
        if not isinstance(chain, str):
            continue
        if not isinstance(items, list):
            continue
        chain_cache: dict[str, dict[str, Any]] = {}
        for item in items:
            # legacy format: list of addresses
            if isinstance(item, str):
                try:
                    address = normalize_address(item)
                except ValueError:
                    continue
                chain_cache[address.lower()] = {"address": address}
                continue
            if not isinstance(item, dict):
                continue
            address_raw = item.get("address")
            if not isinstance(address_raw, str):
                continue
            try:
                address = normalize_address(address_raw)
            except ValueError:
                continue
            chain_cache[address.lower()] = {
                "address": address,
                "id": normalize_id(item.get("id")),
                "asset0": item.get("asset0") if isinstance(item.get("asset0"), str) else None,
                "asset1": item.get("asset1") if isinstance(item.get("asset1"), str) else None,
            }
        if chain_cache:
            cache[chain] = chain_cache
    return cache


def collect_v3_markets(
    deployments_data: dict[str, dict[str, str]],
    min_id: int,
    cache: dict[str, dict[str, dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    result_by_chain: dict[str, dict[str, dict[str, Any]]] = {}

    for chain, markets in deployments_data.items():
        if not isinstance(markets, dict):
            continue
        for market_name, config_address in markets.items():
            if not isinstance(market_name, str) or not isinstance(config_address, str):
                continue
            match = ID_PATTERN.search(market_name)
            if not match:
                continue
            market_id = int(match.group(1))
            if market_id < min_id:
                continue
            try:
                address = normalize_address(config_address)
            except ValueError:
                continue
            chain_map = result_by_chain.setdefault(chain, {})
            chain_map[address.lower()] = {
                "address": address,
                "id": market_id,
                "asset0": None,
                "asset1": None,
            }

    for address, chain_label in EXTRA_MARKETS_RAW:
        chain = normalize_chain_name(chain_label)
        normalized = normalize_address(address)
        chain_map = result_by_chain.setdefault(chain, {})
        chain_map.setdefault(
            normalized.lower(),
            {
                "address": normalized,
                "id": None,
                "asset0": None,
                "asset1": None,
            },
        )

    # merge cache values (id/assets) into current set
    for chain, markets in result_by_chain.items():
        chain_cache = cache.get(chain, {})
        for addr_lower, market in markets.items():
            cached = chain_cache.get(addr_lower)
            if not cached:
                continue
            # deployment id has priority; cache id only for missing ones.
            if market.get("id") is None and cached.get("id") is not None:
                market["id"] = cached["id"]
            if not market.get("asset0") and cached.get("asset0"):
                market["asset0"] = cached["asset0"]
            if not market.get("asset1") and cached.get("asset1"):
                market["asset1"] = cached["asset1"]

    result: dict[str, list[dict[str, Any]]] = {}
    for chain, markets in result_by_chain.items():
        items = list(markets.values())
        items.sort(key=lambda m: ((m.get("id") is None), m.get("id") or 0, m["address"].lower()))
        result[chain] = items

    return dict(sorted(result.items(), key=lambda item: item[0]))


def enrich_chain_with_rpc(chain: str, markets: list[dict[str, Any]], rpc_url: str) -> None:
    preflight_err = rpc_preflight(rpc_url, timeout=20)
    if preflight_err:
        print(f"[warn] {chain}: RPC preflight failed: {preflight_err}")
        return

    # 1) Fill missing IDs from SILO_ID()
    id_missing = [m for m in markets if m.get("id") is None]
    if id_missing:
        id_calls = [(m["address"], SILO_ID_SELECTOR) for m in id_missing]
        id_results, id_err = multicall_eth_calls(chain, rpc_url, id_calls, timeout=180)
        if id_err:
            print(f"[warn] {chain}: SILO_ID multicall failed: {id_err}")
        else:
            for market, (raw, call_err) in zip(id_missing, id_results):
                if call_err or not raw:
                    continue
                market_id = decode_uint256(raw)
                if market_id is not None:
                    market["id"] = market_id

    # 2) Fill missing market names from asset0/asset1
    assets_missing = [
        m
        for m in markets
        if not m.get("asset0") or not m.get("asset1")
    ]
    if not assets_missing:
        return

    # config -> (silo0, silo1)
    silos_calls = [(m["address"], GET_SILOS_SELECTOR) for m in assets_missing]
    silos_results, silos_err = multicall_eth_calls(chain, rpc_url, silos_calls, timeout=180)
    if silos_err:
        print(f"[warn] {chain}: getSilos multicall failed: {silos_err}")
        return

    config_to_silos: dict[str, tuple[str, str]] = {}
    unique_silos: dict[str, str] = {}
    for market, (raw, call_err) in zip(assets_missing, silos_results):
        if call_err or not raw:
            continue
        silos = decode_get_silos(raw)
        if silos is None:
            continue
        silo0, silo1 = silos
        config_to_silos[market["address"].lower()] = (silo0, silo1)
        unique_silos[silo0.lower()] = silo0
        unique_silos[silo1.lower()] = silo1

    if not unique_silos:
        return

    # silo -> token (asset())
    silo_list = list(unique_silos.values())
    asset_calls = [(silo, ASSET_SELECTOR) for silo in silo_list]
    asset_results, asset_err = multicall_eth_calls(chain, rpc_url, asset_calls, timeout=180)
    if asset_err:
        print(f"[warn] {chain}: asset() multicall failed: {asset_err}")
        return

    silo_to_token: dict[str, str] = {}
    for silo, (raw, call_err) in zip(silo_list, asset_results):
        if call_err or not raw:
            continue
        token = decode_abi_address_word(raw)
        if token:
            silo_to_token[silo.lower()] = token

    # token -> symbol
    unique_tokens: dict[str, str] = {}
    for token in silo_to_token.values():
        if token.lower() == "0x" + "0" * 40:
            continue
        unique_tokens[token.lower()] = token

    token_to_symbol: dict[str, str] = {}
    if unique_tokens:
        token_list = list(unique_tokens.values())
        symbol_calls = [(token, SYMBOL_SELECTOR) for token in token_list]
        symbol_results, symbol_err = multicall_eth_calls(chain, rpc_url, symbol_calls, timeout=180)
        if symbol_err:
            print(f"[warn] {chain}: symbol() multicall failed: {symbol_err}")
        else:
            for token, (raw, call_err) in zip(token_list, symbol_results):
                if call_err or not raw:
                    continue
                symbol = decode_symbol(raw)
                if symbol:
                    token_to_symbol[token.lower()] = symbol

    for market in assets_missing:
        silos = config_to_silos.get(market["address"].lower())
        if not silos:
            continue
        silo0, silo1 = silos
        token0 = silo_to_token.get(silo0.lower())
        token1 = silo_to_token.get(silo1.lower())
        if not token0 or not token1:
            continue

        asset0 = token_to_symbol.get(token0.lower(), token0)
        asset1 = token_to_symbol.get(token1.lower(), token1)
        market["asset0"] = asset0
        market["asset1"] = asset1


def enrich_with_rpc(markets_by_chain: dict[str, list[dict[str, Any]]]) -> None:
    for chain, markets in markets_by_chain.items():
        if not markets:
            continue
        needs_rpc = any(
            m.get("id") is None or not m.get("asset0") or not m.get("asset1")
            for m in markets
        )
        if not needs_rpc:
            continue

        rpc_url = get_rpc_url(chain)
        if not rpc_url:
            print(f"[warn] {chain}: missing RPC env, leaving unresolved fields as-is")
            continue

        enrich_chain_with_rpc(chain, markets, rpc_url)


def main() -> int:
    args = parse_args()

    deployments_path = Path(args.deployments)
    output_path = Path(args.output)

    data = json.loads(deployments_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Deployments JSON root must be an object.")

    cache = load_cache(output_path)
    markets = collect_v3_markets(data, min_id=args.min_id, cache=cache)
    if not args.skip_rpc:
        enrich_with_rpc(markets)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(markets, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    total = sum(len(items) for items in markets.values())
    missing_id = sum(1 for items in markets.values() for m in items if m.get("id") is None)
    missing_assets = sum(
        1 for items in markets.values() for m in items if not m.get("asset0") or not m.get("asset1")
    )
    print(
        f"Wrote {output_path} with {total} markets across {len(markets)} chains "
        f"(missing id: {missing_id}, missing assets: {missing_assets})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
