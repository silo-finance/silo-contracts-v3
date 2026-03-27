#!/usr/bin/env python3
"""
Extract new token addresses from Silo configs (via RPC) and add them to common/addresses.

Compares _siloDeployments.json between base and head refs, fetches token addresses from each
new SiloConfig via getSilos()+getAssetForSilo(), gets symbol from ERC20, and adds missing
tokens to common/addresses/{chain}.json.

Usage:
  python3 scripts/sync_tokens_from_deployments.py --base origin/master --head HEAD

  # Dry run (no file writes)
  python3 scripts/sync_tokens_from_deployments.py --base origin/master --head HEAD --dry-run

Environment:
  RPC_MAINNET, RPC_ARBITRUM_ONE, RPC_AVALANCHE, RPC_BASE, RPC_BNB, RPC_INJECTIVE,
  RPC_OPTIMISM, RPC_OKX, RPC_SONIC, RPC_INK, RPC_XDC (same mapping as verify-silo workflow)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CHAIN_RPC_SUFFIX = {
    "mainnet": "MAINNET",
    "arbitrum_one": "ARBITRUM_ONE",
    "avalanche": "AVALANCHE",
    "base": "BASE",
    "bnb": "BNB",
    "injective": "INJECTIVE",
    "optimism": "OPTIMISM",
    "okx": "OKX",
    "sonic": "SONIC",
    "ink": "INK",
    "xdc": "XDC",
}

SILO_DEPLOYMENTS_JSON = "silo-core/deploy/silo/_siloDeployments.json"
COMMON_ADDRESSES_DIR = "common/addresses"

ISILO_CONFIG_ABI = [
    {
        "inputs": [],
        "name": "getSilos",
        "outputs": [
            {"internalType": "address", "name": "silo0", "type": "address"},
            {"internalType": "address", "name": "silo1", "type": "address"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"internalType": "address", "name": "_silo", "type": "address"}],
        "name": "getAssetForSilo",
        "outputs": [{"internalType": "address", "name": "asset", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
]

ERC20_SYMBOL_STRING_ABI = [
    {
        "inputs": [],
        "name": "symbol",
        "outputs": [{"internalType": "string", "name": "", "type": "string"}],
        "stateMutability": "view",
        "type": "function",
    },
]

ERC20_SYMBOL_BYTES32_ABI = [
    {
        "inputs": [],
        "name": "symbol",
        "outputs": [{"internalType": "bytes32", "name": "", "type": "bytes32"}],
        "stateMutability": "view",
        "type": "function",
    },
]


def _get_web3():
    try:
        from web3 import Web3
        return Web3
    except ImportError:
        print("web3 package required. Run: pip install web3", file=sys.stderr)
        sys.exit(1)


def load_deployments_at_ref(repo_root: Path, ref: str) -> dict[str, dict[str, str]]:
    try:
        out = subprocess.run(
            ["git", "show", f"{ref}:{SILO_DEPLOYMENTS_JSON}"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode != 0:
            return {}
        return json.loads(out.stdout)
    except Exception:
        return {}


def find_new_config_addresses(
    repo_root: Path, base_ref: str, head_ref: str
) -> list[tuple[str, str]]:
    base_data = load_deployments_at_ref(repo_root, base_ref)
    head_data = load_deployments_at_ref(repo_root, head_ref)
    new_configs: list[tuple[str, str]] = []
    for chain, markets in head_data.items():
        if chain not in CHAIN_RPC_SUFFIX:
            continue
        base_markets = base_data.get(chain, {})
        for name, config_addr in markets.items():
            if not config_addr or not name:
                continue
            prev = base_markets.get(name)
            addr_lower = config_addr.strip().lower()
            if prev and prev.strip().lower() == addr_lower:
                continue
            new_configs.append((chain, config_addr.strip()))
    return new_configs


def get_rpc_url(chain: str) -> str | None:
    suffix = CHAIN_RPC_SUFFIX.get(chain)
    if not suffix:
        return None
    return os.environ.get(f"RPC_{suffix}")


def fetch_tokens_from_config(Web3, w3, config_address: str) -> list[str]:
    try:
        config = w3.eth.contract(
            address=Web3.to_checksum_address(config_address),
            abi=ISILO_CONFIG_ABI,
        )
        silo0, silo1 = config.functions.getSilos().call()
        token0 = config.functions.getAssetForSilo(silo0).call()
        token1 = config.functions.getAssetForSilo(silo1).call()
        return [token0, token1]
    except Exception as e:
        print(f"  RPC error for config {config_address}: {e}", file=sys.stderr)
        return []


def _decode_bytes32_symbol(raw) -> str | None:
    if raw is None:
        return None
    try:
        b = bytes(raw) if not isinstance(raw, bytes) else raw
        return b.rstrip(b"\x00").decode("utf-8").strip() or None
    except Exception:
        return None


def fetch_symbol(Web3, w3, token_address: str) -> str | None:
    if not token_address or token_address == "0x0000000000000000000000000000000000000000":
        return None
    checksum = Web3.to_checksum_address(token_address)
    try:
        token = w3.eth.contract(address=checksum, abi=ERC20_SYMBOL_STRING_ABI)
        sym = token.functions.symbol().call()
        if sym and isinstance(sym, str):
            sym = re.sub(r"[\s/]+", "_", sym.strip())
            return sym if sym else None
    except Exception:
        pass
    try:
        token = w3.eth.contract(address=checksum, abi=ERC20_SYMBOL_BYTES32_ABI)
        raw = token.functions.symbol().call()
        sym = _decode_bytes32_symbol(raw)
        if sym:
            sym = re.sub(r"[\s/]+", "_", sym.strip())
            return sym if sym else None
    except Exception:
        pass
    return None


def normalize_address(addr: str) -> str:
    return addr.strip().lower() if addr else ""


def collect_new_tokens(
    repo_root: Path,
    base_ref: str,
    head_ref: str,
) -> list[tuple[str, str, str]]:
    Web3 = _get_web3()
    new_configs = find_new_config_addresses(repo_root, base_ref, head_ref)
    if not new_configs:
        return []

    addresses_dir = repo_root / COMMON_ADDRESSES_DIR
    to_add: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()

    for chain, config_addr in new_configs:
        rpc_url = get_rpc_url(chain)
        if not rpc_url:
            print(f"  Skip {chain}: RPC_{CHAIN_RPC_SUFFIX[chain]} not set", file=sys.stderr)
            continue

        try:
            w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 30}))
            if not w3.is_connected():
                print(f"  Skip {chain}: RPC not connected", file=sys.stderr)
                continue
        except Exception as e:
            print(f"  Skip {chain}: {e}", file=sys.stderr)
            continue

        tokens = fetch_tokens_from_config(Web3, w3, config_addr)
        chain_file = addresses_dir / f"{chain}.json"
        existing: dict[str, str] = {}
        if chain_file.exists():
            existing = json.loads(chain_file.read_text(encoding="utf-8"))
        existing_addrs = {normalize_address(v) for v in existing.values()}

        for token_addr in tokens:
            addr_lower = normalize_address(token_addr)
            if (chain, addr_lower) in seen:
                continue
            seen.add((chain, addr_lower))
            if addr_lower in existing_addrs:
                continue

            symbol = fetch_symbol(Web3, w3, token_addr)
            if not symbol:
                print(f"  Skip token {token_addr}: could not fetch symbol", file=sys.stderr)
                continue

            if symbol in existing and normalize_address(existing[symbol]) != addr_lower:
                print(
                    f"  Skip {symbol}: already exists with different address",
                    file=sys.stderr,
                )
                continue

            to_add.append((chain, symbol, token_addr))

    return to_add


def apply_additions(
    repo_root: Path,
    to_add: list[tuple[str, str, str]],
    dry_run: bool,
) -> None:
    addresses_dir = repo_root / COMMON_ADDRESSES_DIR
    by_chain: dict[str, list[tuple[str, str]]] = {}
    for chain, symbol, addr in to_add:
        if dry_run:
            print(f"  Would add {chain}: {symbol} = {addr}")
            continue
        by_chain.setdefault(chain, []).append((symbol, addr))

    for chain, entries in by_chain.items():
        chain_file = addresses_dir / f"{chain}.json"
        data: dict[str, str] = {}
        if chain_file.exists():
            data = json.loads(chain_file.read_text(encoding="utf-8"))
        for symbol, addr in entries:
            data[symbol] = addr
            print(f"  Added {chain}: {symbol} = {addr}")
        data = dict(sorted(data.items()))
        with chain_file.open("w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, separators=(",", ": "), ensure_ascii=False)
            f.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync new tokens from Silo deployments to common/addresses.",
    )
    parser.add_argument("--base", required=True, help="Base git ref (e.g. origin/master)")
    parser.add_argument("--head", default="HEAD", help="Head git ref (default: HEAD)")
    parser.add_argument("--dry-run", action="store_true", help="Print changes only")
    parser.add_argument(
        "--summary",
        metavar="FILE",
        help="Write JSON summary of added tokens (for CI)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    if not (repo_root / SILO_DEPLOYMENTS_JSON).exists():
        print(f"Not found: {SILO_DEPLOYMENTS_JSON}", file=sys.stderr)
        return 1

    to_add = collect_new_tokens(repo_root, args.base, args.head)
    if not to_add:
        print("No new tokens to add.")
        if args.summary:
            Path(args.summary).write_text(
                json.dumps({"added": []}, indent=2),
                encoding="utf-8",
            )
        return 0

    apply_additions(repo_root, to_add, args.dry_run)

    summary = {"added": [{"chain": c, "symbol": s, "address": a} for c, s, a in to_add]}
    if args.summary:
        Path(args.summary).write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(f"Summary written to {args.summary}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
