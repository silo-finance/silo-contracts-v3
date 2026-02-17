#!/usr/bin/env python3
"""
Fetch Standard JSON for a verified contract and save it locally.

This script mirrors the behavior from Hardhat tasks:
- tasks/getStandardJson.ts
- tasks/lineaVerifyCode.ts

It only downloads `SourceCode` from explorer API and writes a `.standard.json` file.

It also auto-loads environment variables from repo-local `env` (preferred) or `.env`.

Examples (Arbitrum):

    # Load env vars (optional, the script also auto-loads `./env` / `./.env`)
    source ./env 2>/dev/null || true

    # Download Standard JSON from Arbiscan
    python3 scripts/get_standard_json.py \
        --network arbitrum_one \
        --address 0x3F6Bf00619eCe8d739e453F5fb43C4cB58E82B24

    # Explorer API URL override (used for ANY chain if set):
    # export VERIFIER_URL_ETHERSCAN_V2=https://api.etherscan.io/v2/api
    #
    # Or chain-specific URL override (used only if VERIFIER_URL_ETHERSCAN_V2 is not set):
    # export VERIFIER_URL_ARBISCAN=https://api.arbiscan.io/api
    # export ARBISCAN_API_KEY=...
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen


EXPLORER_CONFIG = {
    # Note: URLs can be overridden via env vars (VERIFIER_URL_*)
    "mainnet": {
        "api_url_default": "https://api.etherscan.io/api",
        "api_url_env": "VERIFIER_URL_MAINNET",
        "api_key_envs": ["ETHERSCAN_API_KEY"],
        "chainid": 1,
    },
    "ethereum_mainnet": {
        "api_url_default": "https://api.etherscan.io/api",
        "api_url_env": "VERIFIER_URL_MAINNET",
        "api_key_envs": ["ETHERSCAN_API_KEY"],
        "chainid": 1,
    },
    "arbitrum_one": {
        "api_url_default": "https://api.arbiscan.io/api",
        "api_url_env": "VERIFIER_URL_ARBISCAN",
        # Prefer Arbiscan key, but allow Etherscan key for unified v2 endpoint setups.
        "api_key_envs": ["ARBISCAN_API_KEY", "ETHERSCAN_API_KEY"],
        "chainid": 42161,
    },
    # Kept for backwards-compatibility with older usage.
    "avalanche_production": {
        "api_url_default": "https://api.snowtrace.io/api",
        "api_url_env": "VERIFIER_URL_AVALANCHE",
        "api_key_envs": ["AVASCAN_API_KEY"],
        "chainid": 43114,
    },
    "linea_production": {
        "api_url_default": "https://api.lineascan.build/api",
        "api_url_env": "VERIFIER_URL_LINEA",
        "api_key_envs": ["LINEASCAN_API_KEY"],
        "chainid": 59144,
    },
}


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
        return value[1:-1]
    return value


def load_repo_env(repo_root: Path, *, override_existing: bool = False) -> Path | None:
    """
    Load environment variables from repo-local `env` (preferred) or `.env`.

    Supports lines like:
      - export KEY=value
      - KEY=value
    Ignores blank lines and comments (#...).
    """
    candidates = [
        repo_root / "env",
        repo_root / ".env",
    ]

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
        value = _strip_quotes(value)
        if not key:
            continue

        if override_existing or key not in os.environ:
            os.environ[key] = value

    return env_path


def _get_first_env(*names: str) -> str:
    for name in names:
        if not name:
            continue
        value = os.getenv(name, "").strip()
        if value:
            return value
    return ""


def _safe_filename(value: str) -> str:
    """
    Make a conservative filename from user/API-provided string.
    Keeps [a-zA-Z0-9._-], replaces others with '_'.
    """
    value = (value or "").strip()
    if not value:
        return ""
    out: list[str] = []
    for ch in value:
        if ch.isalnum() or ch in "._-":
            out.append(ch)
        else:
            out.append("_")
    # collapse repeats a bit
    return "".join(out).strip("._-") or ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download contract SourceCode and save Standard JSON."
    )
    parser.add_argument(
        "--address",
        required=True,
        help="Contract address with verified source code on explorer API.",
    )
    parser.add_argument(
        "--contract",
        default="",
        help="Optional contract name used in output filename. "
        "If omitted, script uses ContractName from explorer response.",
    )
    parser.add_argument(
        "--network",
        default="arbitrum_one",
        choices=sorted(EXPLORER_CONFIG.keys()),
        help="Network key used to pick explorer API and env API key.",
    )
    parser.add_argument(
        "--output-dir",
        default="flattened",
        help="Directory where the .standard.json file will be written.",
    )
    parser.add_argument(
        "--api-key",
        default="",
        help="Optional explicit API key. If omitted, script reads from env.",
    )
    parser.add_argument(
        "--chainid",
        type=int,
        default=0,
        help="Optional chain id override (used when calling Etherscan V2 API).",
    )
    parser.add_argument(
        "--env-file",
        default="",
        help="Optional explicit env file path. Defaults to repo `env` or `.env`.",
    )
    return parser.parse_args()


def fetch_source_code(
    api_url: str, api_key: str, address: str, *, chainid: int | None
) -> tuple[str, str]:
    def _redact_apikey(url: str) -> str:
        # Avoid leaking secrets in logs while still showing full request structure.
        key = "apikey="
        idx = url.find(key)
        if idx == -1:
            return url
        start = idx + len(key)
        end = url.find("&", start)
        if end == -1:
            end = len(url)
        return url[:start] + "<redacted>" + url[end:]

    params = {
        "module": "contract",
        "action": "getsourcecode",
        "address": address,
        "apikey": api_key,
    }

    # Etherscan V2 API requires `chainid` parameter.
    # It is safe to omit for V1, and safe to include only when V2 is detected.
    is_v2 = "/v2/" in api_url
    if is_v2:
        if not chainid:
            raise RuntimeError(
                "Missing chainid for Etherscan V2 API. "
                "Pass --chainid or use a --network with configured chainid."
            )
        params["chainid"] = str(chainid)
    url = f"{api_url}?{urlencode(params)}"

    try:
        # First thing: print the exact URL we are about to call (redacted).
        print(f"Explorer request URL: {_redact_apikey(url)}", file=sys.stderr, flush=True)
        with urlopen(url) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        raise RuntimeError(f"HTTP error while calling explorer API: {exc}") from exc
    except URLError as exc:
        raise RuntimeError(f"Network error while calling explorer API: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError("Explorer API returned invalid JSON.") from exc

    # On errors Etherscan-style APIs return status=0, message=NOTOK, result=<string>.
    if payload.get("status") == "0":
        raise RuntimeError(f"Explorer API error: {payload.get('result', payload)}")

    result = payload.get("result")
    if not isinstance(result, list) or not result:
        raise RuntimeError(f"Unexpected explorer response: {payload}")

    contract_data = result[0]
    contract_name = (contract_data.get("ContractName") or "").strip()
    source_code = contract_data.get("SourceCode", "")
    if not source_code:
        raise RuntimeError("SourceCode is empty in explorer response.")

    if "Contract source code not verified" in json.dumps(contract_data):
        raise RuntimeError("Contract source code not verified.")

    # Keep behavior aligned with TS tasks: some explorers wrap standard-json in "{{...}}".
    if source_code.startswith("{{") and source_code.endswith("}}") and len(source_code) >= 4:
        return source_code[1:-1], contract_name
    return source_code, contract_name


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]

    # Load env vars from repo by default, so running the script "just works".
    if args.env_file:
        env_path = Path(args.env_file).expanduser().resolve()
        if env_path.exists() and env_path.is_file():
            load_repo_env(env_path.parent, override_existing=False)  # best-effort
            # Also load the explicitly provided file itself.
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
                value = _strip_quotes(value)
                if key and key not in os.environ:
                    os.environ[key] = value
        else:
            print(f"Warning: --env-file not found: {env_path}", file=sys.stderr)
    else:
        load_repo_env(repo_root, override_existing=False)

    cfg = EXPLORER_CONFIG[args.network]

    # In this repo we always prefer the unified Etherscan V2-style URL override,
    # regardless of chain.
    api_url_override = os.getenv("VERIFIER_URL_ETHERSCAN_V2", "").strip()
    api_url = api_url_override or os.getenv(cfg.get("api_url_env", ""), "") or cfg["api_url_default"]
    api_key_envs = cfg.get("api_key_envs") or ([cfg["api_key_env"]] if "api_key_env" in cfg else [])
    api_key = args.api_key or _get_first_env(*api_key_envs)
    chainid = args.chainid or int(cfg.get("chainid", 0) or 0) or None
    if not api_key:
        print(
            f"Warning: API key is empty. Set one of: {', '.join(api_key_envs)} "
            "or pass --api-key if explorer requires it.",
            file=sys.stderr,
        )

    print(f"Fetching source for address {args.address}...", file=sys.stderr)
    source_code, detected_name = fetch_source_code(
        api_url=api_url,
        api_key=api_key,
        address=args.address,
        chainid=chainid,
    )

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    chosen_name = args.contract.strip() or detected_name or args.address
    safe_name = _safe_filename(chosen_name) or _safe_filename(args.address) or "contract"
    if detected_name and not args.contract.strip():
        print(f"Detected contract name: {detected_name}", file=sys.stderr)

    output_path = output_dir / f"{safe_name}.standard.json"
    output_path.write_text(source_code, encoding="utf-8")

    print("Standard JSON saved:")
    print(output_path.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
