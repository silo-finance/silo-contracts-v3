#!/usr/bin/env python3
"""
Check deployment contract verification on explorer APIs (no HTML scraping).

This script is matrix-friendly for CI:
  python3 scripts/check_deployments_verified_on_explorer.py --chain arbitrum_one

It collects addresses from:
  - */deployments/<chain>/*.json ("address")
  - */broadcast/**/<chain_id>/run-latest.json (nested contractName+contractAddress, including libraries)

Then, for each address, it calls explorer API (etherscan-compatible):
  module=contract&action=getsourcecode&address=<address>&apikey=<api_key>

Status output per contract:
  [chain] or [chain explorer] component/contract_name address Verified|Not Verified
  (For Avalanche both routescan and etherscan are checked; explorer name in brackets.)

Summary:
  One line per (chain, explorer). For Avalanche: Summary [avalanche routescan]: ... and Summary [avalanche etherscan]: ...

Env vars per chain:
  EXPLORER_API_KEY_<CHAIN>
  EXPLORER_API_URL_<CHAIN>   (optional override)

Example for arbitrum_one:
  EXPLORER_API_KEY_ARBITRUM_ONE=...
  EXPLORER_API_URL_ARBITRUM_ONE=https://api.arbiscan.io/api   # optional (default exists)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

COMPONENT_PATHS = {
    "core": "silo-core",
    "oracle": "silo-oracles",
    "vaults": "silo-vaults",
}

CHAIN_TO_CHAIN_ID: dict[str, str] = {
    "mainnet": "1",
    "optimism": "10",
    "bnb": "56",
    "arbitrum_one": "42161",
    "avalanche": "43114",
    "sonic": "146",
    "okx": "196",
    "base": "8453",
    "ink": "57073",
    "injective": "1776",
}

# Defaults for etherscan-compatible endpoints.
# Chains with multiple explorers (e.g. avalanche) list (label, url) tuples.
# You can override via EXPLORER_API_URL_<CHAIN> for single-explorer chains.
CHAIN_EXPLORERS: dict[str, list[tuple[str, str]]] = {
    "arbitrum_one": [("default", "https://api.etherscan.io/v2/api?chainid=42161")],
    "avalanche": [
        ("routescan", "https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan/api"),
        ("etherscan", "https://api.etherscan.io/v2/api?chainid=43114"),
    ],
    "base": [("default", "https://api.etherscan.io/v2/api?chainid=8453")],
    "bnb": [("default", "https://api.etherscan.io/v2/api?chainid=56")],
    "mainnet": [("default", "https://api.etherscan.io/v2/api?chainid=1")],
    "optimism": [("default", "https://api.etherscan.io/v2/api?chainid=10")],
    "okx": [("default", "https://www.oklink.com/api/explorer/v1/eth/api")],
    "sonic": [("default", "https://api.etherscan.io/v2/api?chainid=146")],
}

USER_AGENT = "Mozilla/5.0 (compatible; explorer-api-verify-checker/1.0)"


@dataclass(frozen=True)
class ContractEntry:
    chain: str
    component: str
    contract_name: str
    address: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Check deployment verification status using explorer API.")
    p.add_argument(
        "--chain",
        required=True,
        help="Chain name or comma-separated list (e.g. arbitrum_one or mainnet,base). Use 'all' for all chains.",
    )
    p.add_argument(
        "--components",
        default="core,oracle,vaults",
        help="Comma-separated list: core,oracle,vaults. Default: all.",
    )
    p.add_argument("--timeout", type=int, default=20, help="HTTP timeout in seconds. Default: 20.")
    p.add_argument("--verbose", action="store_true", help="Print API endpoint info and errors.")
    return p.parse_args()


def chain_env_suffix(chain: str) -> str:
    return chain.upper().replace("-", "_")


def parse_chain_selection(raw: str) -> list[str]:
    if raw.strip().lower() == "all":
        return sorted(CHAIN_TO_CHAIN_ID.keys())
    chains = [c.strip() for c in raw.split(",") if c.strip()]
    unknown = [c for c in chains if c not in CHAIN_TO_CHAIN_ID]
    if unknown:
        raise ValueError(f"Unknown chain(s): {unknown}. Allowed: {sorted(CHAIN_TO_CHAIN_ID.keys())}")
    return chains


def parse_components(raw: str) -> list[str]:
    components = [c.strip() for c in raw.split(",") if c.strip()]
    unknown = [c for c in components if c not in COMPONENT_PATHS]
    if unknown:
        raise ValueError(f"Unknown component(s): {unknown}. Allowed: {sorted(COMPONENT_PATHS.keys())}")
    return components


def resolve_api_config(chain: str) -> tuple[list[tuple[str, str]], str]:
    """
    Return (explorer_configs, api_key).
    explorer_configs: list of (label, api_url) - one or more per chain (avalanche has two).
    """
    suffix = chain_env_suffix(chain)
    url_env = f"EXPLORER_API_URL_{suffix}"
    key_env = "ETHERSCAN_API_KEY"

    api_key = os.environ.get(key_env)
    if not api_key:
        raise ValueError(f"API key not set for chain={chain}. Set {key_env}.")

    env_url = os.environ.get(url_env)
    if env_url:
        # Env override: single explorer
        return [("default", env_url)], api_key

    explorers = CHAIN_EXPLORERS.get(chain)
    if not explorers:
        raise ValueError(
            f"API URL not configured for chain={chain}. Set {url_env}."
        )
    return explorers, api_key


def _normalize_name(file_name: str) -> str:
    return file_name[:-4] if file_name.endswith(".sol") else file_name


def _is_address(value: Any) -> bool:
    return isinstance(value, str) and value.startswith("0x") and len(value) >= 42


def collect_from_deployments(repo_root: Path, chain: str, component: str) -> list[ContractEntry]:
    base = repo_root / COMPONENT_PATHS[component] / "deployments" / chain
    if not base.exists():
        return []

    out: list[ContractEntry] = []
    for jf in base.glob("*.json"):
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        addr = data.get("address")
        if not _is_address(addr):
            continue
        out.append(
            ContractEntry(
                chain=chain,
                component=component,
                contract_name=_normalize_name(jf.stem),
                address=addr.lower(),
            )
        )
    return out


def _extract_contract_entries_from_obj(
    obj: Any, chain: str, component: str, out: list[ContractEntry]
) -> None:
    if isinstance(obj, dict):
        contract_name = obj.get("contractName")
        contract_addr = obj.get("contractAddress")
        if isinstance(contract_name, str) and _is_address(contract_addr):
            out.append(
                ContractEntry(
                    chain=chain,
                    component=component,
                    contract_name=contract_name.strip(),
                    address=contract_addr.lower(),
                )
            )
        for v in obj.values():
            _extract_contract_entries_from_obj(v, chain, component, out)
    elif isinstance(obj, list):
        for item in obj:
            _extract_contract_entries_from_obj(item, chain, component, out)


def collect_from_broadcast(repo_root: Path, chain: str, component: str) -> list[ContractEntry]:
    chain_id = CHAIN_TO_CHAIN_ID[chain]
    base = repo_root / COMPONENT_PATHS[component] / "broadcast"
    if not base.exists():
        return []

    out: list[ContractEntry] = []
    for run_file in base.glob(f"**/{chain_id}/run-latest.json"):
        try:
            data = json.loads(run_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        _extract_contract_entries_from_obj(data, chain, component, out)
    return out


def collect_contracts(repo_root: Path, chain: str, components: list[str]) -> list[ContractEntry]:
    # Dedup by (component, address); keep first non-empty name.
    dedup: dict[tuple[str, str], ContractEntry] = {}

    for component in components:
        for entry in collect_from_deployments(repo_root, chain, component):
            dedup[(entry.component, entry.address)] = entry

        for entry in collect_from_broadcast(repo_root, chain, component):
            key = (entry.component, entry.address)
            prev = dedup.get(key)
            if prev is None or prev.contract_name.lower() in {"", "unknown"}:
                dedup[key] = entry

    result = list(dedup.values())
    result.sort(key=lambda e: (e.component, e.contract_name.lower(), e.address))
    return result


def fetch_getsourcecode(
    api_url: str, api_key: str, address: str, timeout: int
) -> tuple[dict[str, Any] | None, str | None]:
    query = urlencode(
        {
            "module": "contract",
            "action": "getsourcecode",
            "address": address,
            "apikey": api_key,
        }
    )
    # api_url may already contain ?chainid=... (v2); append params with & not ?
    separator = "&" if "?" in api_url else "?"
    url = f"{api_url}{separator}{query}"

    req = Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        method="GET",
    )
    try:
        with urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
    except (HTTPError, URLError, OSError) as e:
        return None, str(e)

    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return None, f"non-json API response: {body[:200]}"

    if not isinstance(payload, dict):
        return None, f"unexpected API payload type: {type(payload).__name__}"
    return payload, None


def is_verified_from_getsourcecode(payload: dict[str, Any]) -> tuple[bool, str | None]:
    result = payload.get("result")
    if not isinstance(result, list) or not result:
        return False, "missing result[]"

    entry = result[0]
    if not isinstance(entry, dict):
        return False, "result[0] is not object"

    source_code = str(entry.get("SourceCode") or "").strip()
    abi = str(entry.get("ABI") or "").strip().lower()
    contract_name = str(entry.get("ContractName") or "").strip()

    # Etherscan-compatible "not verified" marker often appears in ABI field.
    if "contract source code not verified" in abi:
        return False, None

    # Verified contracts should have source code and name.
    if source_code and contract_name:
        return True, None

    return False, None


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]

    try:
        chains = parse_chain_selection(args.chain)
        components = parse_components(args.components)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 2

    unverified: list[tuple[str, str, ContractEntry]] = []  # (chain, explorer_label, entry)
    has_failures = False

    for chain in chains:
        try:
            explorer_configs, api_key = resolve_api_config(chain)
        except ValueError as e:
            print(str(e), file=sys.stderr)
            return 2

        contracts = collect_contracts(repo_root, chain, components)
        if not contracts:
            continue

        for explorer_label, api_url in explorer_configs:
            if args.verbose:
                print(f"[verbose] chain={chain} explorer={explorer_label} api_url={api_url}", file=sys.stderr)

            verified_count = 0
            not_verified_count = 0
            fetch_error_count = 0

            for c in contracts:
                payload, err = fetch_getsourcecode(api_url, api_key, c.address, timeout=args.timeout)
                if err is not None:
                    if args.verbose:
                        print(f"[verbose] {chain} {c.address} API error: {err}", file=sys.stderr)
                    display = f"[{chain}]" if len(explorer_configs) == 1 else f"[{chain} {explorer_label}]"
                    print(f"{display} {c.component}/{c.contract_name} {c.address} Not Verified")
                    not_verified_count += 1
                    fetch_error_count += 1
                    unverified.append((chain, explorer_label, c))
                    continue

                verified, _reason = is_verified_from_getsourcecode(payload)
                display = f"[{chain}]" if len(explorer_configs) == 1 else f"[{chain} {explorer_label}]"
                if verified:
                    print(f"{display} {c.component}/{c.contract_name} {c.address} Verified")
                    verified_count += 1
                else:
                    print(f"{display} {c.component}/{c.contract_name} {c.address} Not Verified")
                    not_verified_count += 1
                    unverified.append((chain, explorer_label, c))

            if not_verified_count > 0 or fetch_error_count > 0:
                has_failures = True

            # Summary on new lines with clear formatting
            summary_label = f"{chain} {explorer_label}" if len(explorer_configs) > 1 else chain
            print()
            print(f"Summary [{summary_label}]:")
            print(f"  Verified:     {verified_count}")
            print(f"  Not verified: {not_verified_count}")
            print(f"  Fetch errors: {fetch_error_count}")

    # List unverified contracts at the end
    if unverified:
        print()
        print("=" * 60)
        print("Unverified contracts:")
        print("=" * 60)
        for chain, explorer_label, c in unverified:
            label = f"{chain} {explorer_label}" if explorer_label != "default" else chain
            print(f"  [{label}] {c.component}/{c.contract_name}  {c.address}")
        print()

    return 1 if has_failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

