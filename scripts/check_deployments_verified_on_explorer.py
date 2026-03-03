#!/usr/bin/env python3
"""

/api/v5/xlayer/contract/verify-contract-info?chainShortName=xlayer&contractAddress=0xcF80631b469A54dcba8c8ee1aF84505f496ed248
https://web3.okx.com/xlayer/onchaindata/docs/en/#quickstart-guide-api-authentication

OKX/X Layer uses OKLink API (not Etherscan-style):
  GET https://www.oklink.com/api/v5/explorer/contract/verify-contract-info?chainShortName=XLAYER&contractAddress=<addr>
  Response: { "code": "0", "data": [{ "sourceCode": "...", "contractName": "..." }] } when verified.

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
  ETHERSCAN_API_KEY=...
  EXPLORER_API_URL_ARBITRUM_ONE=https://api.arbiscan.io/api   # optional (default exists)

Injective uses Blockscout (https://docs.blockscout.com/devs/apis/rpc); apikey is optional for Blockscout.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
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
# Injective uses Blockscout (https://docs.blockscout.com/devs/apis/rpc) - same getsourcecode API.
CHAIN_EXPLORERS: dict[str, list[tuple[str, str]]] = {
    "arbitrum_one": [("default", "https://api.etherscan.io/v2/api?chainid=42161")],
    # Both use Etherscan-compatible getsourcecode. api.etherscan.io/v2?chainid=43114 returns
    # "not verified" for Avalanche; api.snowtrace.io is Snowtrace's native API (correct data).
    "avalanche": [
        ("routescan", "https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan/api"),
        ("etherscan", "https://api.snowtrace.io/api"),
    ],
    "base": [("default", "https://api.etherscan.io/v2/api?chainid=8453")],
    "injective": [("default", "https://blockscout-api.injective.network/api")],
    "bnb": [("default", "https://api.etherscan.io/v2/api?chainid=56")],
    "mainnet": [("default", "https://api.etherscan.io/v2/api?chainid=1")],
    "optimism": [("default", "https://api.etherscan.io/v2/api?chainid=10")],
    # OKX uses OKLink verify-contract-info (see fetch_oklink_verify_contract_info), not Etherscan-style API
    "okx": [("default", "https://www.oklink.com/api/v5/explorer/contract/verify-contract-info")],
    "sonic": [("default", "https://api.etherscan.io/v2/api?chainid=146")],
}

# Chains that have explorer config (for --chain all; excludes e.g. ink)
VERIFICATION_SUPPORTED_CHAINS = sorted(CHAIN_EXPLORERS.keys())

# Block explorer address URL for PR comment links (display_label -> base URL)
EXPLORER_ADDRESS_URL: dict[str, str] = {
    "Arbitrum": "https://arbiscan.io/address/",
    "Avalanche (routescan)": "https://snowtrace.io/address/",
    "Avalanche (etherscan)": "https://snowscan.xyz/address/",
    "Base": "https://basescan.org/address/",
    "BNB": "https://bscscan.com/address/",
    "Injective": "https://blockscout.injective.network/address/",
    "Mainnet": "https://etherscan.io/address/",
    "Optimism": "https://optimistic.etherscan.io/address/",
    "OKX": "https://www.oklink.com/x-layer/address/",
    "Sonic": "https://sonicscan.org/address/",
}

# Display names for PR comment output
CHAIN_DISPLAY_NAMES: dict[str, str] = {
    "arbitrum_one": "Arbitrum",
    "avalanche": "Avalanche",
    "base": "Base",
    "bnb": "BNB",
    "injective": "Injective",
    "mainnet": "Mainnet",
    "optimism": "Optimism",
    "okx": "OKX",
    "sonic": "Sonic",
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
        help="Chain name or comma-separated list (e.g. arbitrum_one or mainnet,base). Use 'all' for all supported chains.",
    )
    p.add_argument(
        "--components",
        default="core,oracle,vaults",
        help="Comma-separated list: core,oracle,vaults. Default: all.",
    )
    p.add_argument("--timeout", type=int, default=20, help="HTTP timeout in seconds. Default: 20.")
    p.add_argument(
        "--delay",
        type=float,
        default=0.25,
        help="Minimum seconds between API request starts (avoids rate limiting). Sleep only if the previous request took less. Default: 0.25 (4 req/s).",
    )
    p.add_argument("--verbose", action="store_true", help="Print API endpoint info and errors.")
    p.add_argument(
        "--no-fail",
        action="store_true",
        help="Always return exit code 0 (for CI that must not fail on unverified contracts).",
    )
    p.add_argument(
        "--output-unverified-file",
        metavar="PATH",
        help="Write only the 'Unverified contracts' section to this file (for PR comments). If none, writes a success message.",
    )
    p.add_argument(
        "--output-json-file",
        metavar="PATH",
        help="Write per-chain result as JSON for CI merge (used with matrix strategy).",
    )
    return p.parse_args()


def chain_env_suffix(chain: str) -> str:
    return chain.upper().replace("-", "_")


def parse_chain_selection(raw: str) -> list[str]:
    if raw.strip().lower() == "all":
        return VERIFICATION_SUPPORTED_CHAINS
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
    key_env_suffix = f"ETHERSCAN_API_KEY_{suffix}"
    key_env_default = "ETHERSCAN_API_KEY"

    api_key = os.environ.get(key_env_suffix) or os.environ.get(key_env_default)
    if not api_key:
        raise ValueError(
            f"API key not set for chain={chain}. Set {key_env_suffix} or {key_env_default}."
        )

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


def find_contract_source_path(repo_root: Path, component: str, contract_name: str) -> str | None:
    """Find the source .sol file path for a contract. Returns relative path or None."""
    base = repo_root / COMPONENT_PATHS[component]
    if not base.exists():
        return None
    # Search in contracts/ (and subdirs) for {contract_name}.sol
    contracts_dir = base / "contracts"
    if not contracts_dir.exists():
        return None
    matches = sorted(contracts_dir.glob(f"**/{contract_name}.sol"))
    if not matches:
        return None
    return str(matches[0].relative_to(repo_root)).replace("\\", "/")


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


def _is_retriable_error(err: Exception) -> bool:
    """True if error suggests retry (timeout, rate limit, 5xx)."""
    if isinstance(err, HTTPError):
        return err.code in (408, 429, 500, 502, 503, 504)
    if isinstance(err, (URLError, OSError)):
        return True  # timeout, connection refused, etc.
    return False


def fetch_getsourcecode(
    api_url: str, api_key: str, address: str, timeout: int, retry_delay: float = 1.0
) -> tuple[dict[str, Any] | None, str | None]:
    """Fetch getsourcecode. On retriable error (HTTP!=200, timeout), retry once after retry_delay."""
    query = urlencode(
        {
            "module": "contract",
            "action": "getsourcecode",
            "address": address,
            "apikey": api_key,
        }
    )
    separator = "&" if "?" in api_url else "?"
    url = f"{api_url}{separator}{query}"
    req = Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        method="GET",
    )

    last_err: str | None = None
    for attempt in range(2):
        try:
            with urlopen(req, timeout=timeout) as resp:
                body = resp.read().decode("utf-8", errors="ignore")
        except (HTTPError, URLError, OSError) as e:
            last_err = str(e)
            if _is_retriable_error(e) and attempt == 0:
                time.sleep(retry_delay)
                continue
            return None, last_err

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            return None, f"non-json API response: {body[:200]}"

        if not isinstance(payload, dict):
            return None, f"unexpected API payload type: {type(payload).__name__}"

        # Etherscan can return 200 with rate-limit message in JSON
        msg = str(payload.get("message", "")).lower()
        result = payload.get("result")
        if ("rate limit" in msg or "max rate" in msg or "too many" in msg) and attempt == 0:
            time.sleep(retry_delay)
            continue
        if isinstance(result, str) and ("rate limit" in result.lower() or "max rate" in result.lower()) and attempt == 0:
            time.sleep(retry_delay)
            continue

        return payload, None

    return None, last_err or "unknown error"


def is_verified_from_getsourcecode(payload: dict[str, Any]) -> tuple[bool, str | None]:
    """Parse getsourcecode response. Supports both Etherscan (result=list) and Blockscout (result=dict)."""
    result = payload.get("result")
    if result is None:
        return False, "missing result"

    # Etherscan: result is list of one entry; Blockscout: result is single dict
    if isinstance(result, list):
        if not result:
            return False, "empty result[]"
        entry = result[0]
    elif isinstance(result, dict):
        entry = result
    else:
        return False, "result is not list or dict"

    if not isinstance(entry, dict):
        return False, "entry is not object"

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


# OKLink API: GET verify-contract-info (OKX/X Layer and other OKLink-supported chains)
OKLINK_VERIFY_INFO_CHAIN = "XLAYER"  # chainShortName for X Layer


def fetch_oklink_verify_contract_info(
    api_key: str, address: str, timeout: int, retry_delay: float = 1.0
) -> tuple[dict[str, Any] | None, str | None]:
    """Fetch OKLink verify-contract-info. On retriable error, retry once after retry_delay."""
    url = (
        "https://www.oklink.com/api/v5/explorer/contract/verify-contract-info"
        f"?chainShortName={OKLINK_VERIFY_INFO_CHAIN}&contractAddress={address}"
    )
    req = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Ok-Access-Key": api_key,
        },
        method="GET",
    )

    last_err: str | None = None
    for attempt in range(2):
        try:
            with urlopen(req, timeout=timeout) as resp:
                body = resp.read().decode("utf-8", errors="ignore")
        except (HTTPError, URLError, OSError) as e:
            last_err = str(e)
            if _is_retriable_error(e) and attempt == 0:
                time.sleep(retry_delay)
                continue
            return None, last_err

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            return None, f"non-json API response: {body[:200]}"

        if not isinstance(payload, dict):
            return None, f"unexpected API payload type: {type(payload).__name__}"

        msg = str(payload.get("msg", "")).lower()
        if ("rate limit" in msg or "too many" in msg) and attempt == 0:
            time.sleep(retry_delay)
            continue

        return payload, None

    return None, last_err or "unknown error"


def is_verified_from_oklink(payload: dict[str, Any]) -> tuple[bool, str | None]:
    """Parse OKLink verify-contract-info response. Verified when code=='0' and data has sourceCode."""
    code = str(payload.get("code", "")).strip()
    if code != "0":
        return False, f"API code={code} msg={payload.get('msg', '')}"

    data = payload.get("data")
    if not isinstance(data, list) or not data:
        return False, None  # Not verified: empty or missing data

    entry = data[0] if isinstance(data[0], dict) else None
    if not entry:
        return False, None

    source_code = str(entry.get("sourceCode") or "").strip()
    if source_code:
        return True, None
    return False, None


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    unverified: list[tuple[str, str, ContractEntry]] = []
    errors: list[tuple[str, str, ContractEntry]] = []
    # Per chain: (display_label, verified, not_verified, fetch_errors, chain_unverified, chain_errors, config_error?)
    summary_per_chain: list[tuple[str, int, int, int, list[ContractEntry], list[ContractEntry], str | None]] = []
    output_file = getattr(args, "output_unverified_file", None)

    try:
        chains = parse_chain_selection(args.chain)
        components = parse_components(args.components)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        if output_file:
            _write_unverified_file(
                output_file, [], summary_per_chain=[], error_msg="Verification check could not run. See logs for details.", repo_root=repo_root
            )
        json_file = getattr(args, "output_json_file", None)
        if json_file:
            _write_json_artifact(json_file, [], repo_root)
        return 2

    has_failures = False

    try:
        for chain in chains:
            try:
                explorer_configs, api_key = resolve_api_config(chain)
            except ValueError as e:
                print(str(e), file=sys.stderr)
                has_failures = True
                display_label = CHAIN_DISPLAY_NAMES.get(chain, chain)
                summary_per_chain.append((display_label, 0, 0, 0, [], [], str(e)))
                continue

            contracts = collect_contracts(repo_root, chain, components)
            if not contracts:
                display_label = CHAIN_DISPLAY_NAMES.get(chain, chain)
                summary_per_chain.append((display_label, 0, 0, 0, [], [], "No deployments found for this chain."))
                continue

            for explorer_label, api_url in explorer_configs:
                if args.verbose:
                    print(f"[verbose] chain={chain} explorer={explorer_label} api_url={api_url}", file=sys.stderr)

                verified_count = 0
                not_verified_count = 0
                fetch_error_count = 0
                chain_unverified: list[ContractEntry] = []
                chain_errors: list[ContractEntry] = []

                use_oklink = chain == "okx"
                for i, c in enumerate(contracts):
                    if i > 0:
                        elapsed = time.perf_counter() - last_request_start
                        if elapsed < args.delay:
                            time.sleep(args.delay - elapsed)
                    last_request_start = time.perf_counter()
                    if use_oklink:
                        payload, err = fetch_oklink_verify_contract_info(
                            api_key, c.address, timeout=args.timeout
                        )
                    else:
                        payload, err = fetch_getsourcecode(
                            api_url, api_key, c.address, timeout=args.timeout
                        )
                    if err is not None:
                        if args.verbose:
                            print(f"[verbose] {chain} {c.address} API error: {err}", file=sys.stderr)
                        display = f"[{chain}]" if len(explorer_configs) == 1 else f"[{chain} {explorer_label}]"
                        print(f"{display} {c.component}/{c.contract_name} {c.address} Error (could not check)")
                        fetch_error_count += 1
                        errors.append((chain, explorer_label, c))
                        chain_errors.append(c)
                        continue

                    if use_oklink:
                        verified, oklink_reason = is_verified_from_oklink(payload)
                        if not verified and oklink_reason is not None:
                            # code != "0" means API error (auth, rate limit, etc.), not "not verified"
                            if args.verbose:
                                print(f"[verbose] {chain} {c.address} OKLink API: {oklink_reason}", file=sys.stderr)
                            display = f"[{chain}]" if len(explorer_configs) == 1 else f"[{chain} {explorer_label}]"
                            print(f"{display} {c.component}/{c.contract_name} {c.address} Error (could not check)")
                            fetch_error_count += 1
                            errors.append((chain, explorer_label, c))
                            chain_errors.append(c)
                            continue
                    else:
                        verified, _reason = is_verified_from_getsourcecode(payload)
                    display = f"[{chain}]" if len(explorer_configs) == 1 else f"[{chain} {explorer_label}]"
                    if verified:
                        print(f"{display} {c.component}/{c.contract_name} {c.address} Verified")
                        verified_count += 1
                    else:
                        print(f"{display} {c.component}/{c.contract_name} {c.address} Not Verified")
                        not_verified_count += 1
                        unverified.append((chain, explorer_label, c))
                        chain_unverified.append(c)

                if not_verified_count > 0 or fetch_error_count > 0:
                    has_failures = True

                summary_label = f"{chain} {explorer_label}" if len(explorer_configs) > 1 else chain
                display_label = CHAIN_DISPLAY_NAMES.get(chain, chain)
                if explorer_label != "default":
                    display_label = f"{display_label} ({explorer_label})"
                summary_per_chain.append((display_label, verified_count, not_verified_count, fetch_error_count, chain_unverified, chain_errors, None))

                # Summary on new lines with clear formatting
                print()
                print(f"Summary [{summary_label}]:")
                print(f"  Verified:     {verified_count}")
                print(f"  Not verified: {not_verified_count}")
                print(f"  Fetch errors: {fetch_error_count}")

    except Exception:
        if output_file:
            # Write partial report with error banner so PR comment still gets useful info
            partial = _format_report_for_comment(unverified, summary_per_chain, repo_root)
            content = (
                "⚠️ **Verification check failed with an unexpected error.** See workflow logs for details.\n\n"
                "---\n\n" + partial
            )
            Path(output_file).write_text(
                "<!-- UNVERIFIED_CONTRACTS_REPORT -->\n" + content + "\n<!-- /UNVERIFIED_CONTRACTS_REPORT -->",
                encoding="utf-8",
            )
        json_file = getattr(args, "output_json_file", None)
        if json_file and summary_per_chain:
            _write_json_artifact(json_file, summary_per_chain, repo_root)
        raise

    # List unverified and error contracts at the end
    if unverified or errors:
        print()
        print("=" * 60)
        if unverified:
            print("Unverified contracts:")
            for chain, explorer_label, c in unverified:
                label = f"{chain} {explorer_label}" if explorer_label != "default" else chain
                print(f"  [{label}] {c.component}/{c.contract_name}  {c.address}")
        if errors:
            print("Errors (could not check):")
            for chain, explorer_label, c in errors:
                label = f"{chain} {explorer_label}" if explorer_label != "default" else chain
                print(f"  [{label}] {c.component}/{c.contract_name}  {c.address}")
        print()

    # Write unverified section to file (for CI PR comments) - always when output_file is set
    if output_file:
        _write_unverified_file(output_file, unverified, summary_per_chain, repo_root=repo_root)

    # Write JSON for CI matrix merge (per-chain artifact)
    json_file = getattr(args, "output_json_file", None)
    if json_file:
        _write_json_artifact(json_file, summary_per_chain, repo_root)

    exit_code = 1 if has_failures and not getattr(args, "no_fail", False) else 0
    return exit_code


def _format_report_for_comment(
    unverified: list[tuple[str, str, ContractEntry]],
    summary_per_chain: list[tuple[str, int, int, int, list[ContractEntry], str | None]],
    repo_root: Path,
) -> str:
    """Format full report for PR comment: sections per chain with unverified list under each."""
    lines: list[str] = ["## Deployment verification on block explorers", ""]

    if not summary_per_chain:
        lines.append("All deployment contracts are verified on block explorers.")
        return "\n".join(lines)

    # If all contracts are verified across all chains (no config errors), show a single success message
    all_verified = all(
        config_error is None and not_verified == 0 and fetch_errors == 0
        for _, _, not_verified, fetch_errors, _, _, config_error in summary_per_chain
    )
    if all_verified:
        lines.append("All deployment contracts are verified on block explorers.")
        return "\n".join(lines)

    for chain_label, verified, not_verified, fetch_errors, chain_unverified, chain_errors, config_error in summary_per_chain:
        if config_error is None and not_verified == 0 and fetch_errors == 0:
            lines.append(f"**{chain_label}: all {verified} contracts verified.**")
        elif config_error is not None:
            lines.append(f"### {chain_label}")
            lines.append("")
            lines.append(f"⚠️ **Could not check:** {config_error}")
        else:
            lines.append(f"### {chain_label}")
            lines.append("")
            lines.append(f"- **Verified:** {verified}")
            lines.append(f"- **Not verified:** {not_verified}")
            lines.append(f"- **Errors (could not check):** {fetch_errors}")
            lines.append("")
            if chain_unverified:
                lines.append("**Unverified contracts:**")
                lines.append("")
                for c in chain_unverified:
                    path = find_contract_source_path(repo_root, c.component, c.contract_name)
                    path_display = path if path else f"{c.component}/{c.contract_name}"
                    base_url = EXPLORER_ADDRESS_URL.get(chain_label, "")
                    addr_link = f"[`{c.address}`]({base_url}{c.address})" if base_url else f"`{c.address}`"
                    lines.append(f"- `{path_display}` {addr_link}")
                lines.append("")
            if chain_errors:
                lines.append("**Errors (could not check):**")
                lines.append("")
                for c in chain_errors:
                    path = find_contract_source_path(repo_root, c.component, c.contract_name)
                    path_display = path if path else f"{c.component}/{c.contract_name}"
                    base_url = EXPLORER_ADDRESS_URL.get(chain_label, "")
                    addr_link = f"[`{c.address}`]({base_url}{c.address})" if base_url else f"`{c.address}`"
                    lines.append(f"- `{path_display}` {addr_link}")
                lines.append("")
        lines.append("")
        lines.append("")

    return "\n".join(lines).rstrip()


def _contract_to_dict(c: ContractEntry, repo_root: Path) -> dict[str, str]:
    source_path = find_contract_source_path(repo_root, c.component, c.contract_name)
    result: dict[str, str] = {
        "component": c.component,
        "contract_name": c.contract_name,
        "address": c.address,
    }
    if source_path:
        result["source_path"] = source_path
    return result


def _write_json_artifact(
    path: str,
    summary_per_chain: list[tuple[str, int, int, int, list[ContractEntry], list[ContractEntry], str | None]],
    repo_root: Path,
) -> None:
    """Write per-chain result as JSON for CI matrix merge."""
    sections = []
    for display_label, verified, not_verified, fetch_errors, chain_unverified, chain_errors, config_error in summary_per_chain:
        sections.append({
            "display_label": display_label,
            "verified": verified,
            "not_verified": not_verified,
            "fetch_errors": fetch_errors,
            "config_error": config_error,
            "unverified": [_contract_to_dict(c, repo_root) for c in chain_unverified],
            "errors": [_contract_to_dict(c, repo_root) for c in chain_errors],
        })
    data = {"sections": sections}
    Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")


def _write_unverified_file(
    path: str,
    unverified: list[tuple[str, str, ContractEntry]],
    summary_per_chain: list[tuple[str, int, int, int, list[ContractEntry], str | None]],
    error_msg: str | None = None,
    repo_root: Path | None = None,
) -> None:
    """Write full report to file with markers for CI parsing."""
    if repo_root is None:
        repo_root = Path(__file__).resolve().parents[1]
    if error_msg:
        content = (
            "## Deployment verification on block explorers\n\n"
            f"⚠️ {error_msg}"
        )
    else:
        content = _format_report_for_comment(unverified, summary_per_chain, repo_root)
    body = (
        "<!-- UNVERIFIED_CONTRACTS_REPORT -->\n"
        f"{content}\n"
        "<!-- /UNVERIFIED_CONTRACTS_REPORT -->"
    )
    Path(path).write_text(body, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())

