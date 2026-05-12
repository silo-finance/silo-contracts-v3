#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = Path(__file__).resolve().parents[3]
REPO_SCRIPTS_DIR = REPO_ROOT / "scripts"
if str(REPO_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(REPO_SCRIPTS_DIR))

from rpc_multicall import multicall_eth_calls, rpc_preflight  # noqa: E402

DEFAULT_DEPLOY_JSON = SCRIPT_DIR / "permissioned_liquidation_deploy_gauges_by_chain.json"
DEFAULT_MARKETS_JSON = SCRIPT_DIR / "v3_markets_by_chain.json"
DEFAULT_SIC_JSON = REPO_ROOT / "silo-core/deploy/incentives-controller/_siloIncentivesControllerDeployments.json"

ID_RE = re.compile(r"\((\d+)\)")
KIND_RE = re.compile(r":\s*(Collateral|Protected|Debt)\s*$", re.IGNORECASE)
SHARE_TOKEN_SELECTOR = "0x1d7e3556"  # SHARE_TOKEN()

KIND_TO_SHARE_TOKEN_KIND = {
    "collateral": "collateralShareToken",
    "protected": "protectedShareToken",
    "debt": "debtShareToken",
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


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Synchronize success=false records with _siloIncentivesControllerDeployments.json "
            "and refresh shareToken using multicall."
        )
    )
    p.add_argument("--deploy-json", type=Path, default=DEFAULT_DEPLOY_JSON)
    p.add_argument("--markets-json", type=Path, default=DEFAULT_MARKETS_JSON)
    p.add_argument("--sic-json", type=Path, default=DEFAULT_SIC_JSON)
    p.add_argument("--chain", action="append", default=[], help="Optional chain filter (repeatable).")
    p.add_argument("--dry-run", action="store_true", help="Show changes without writing deploy-json.")
    return p.parse_args()


def is_address(v: Any) -> bool:
    if not isinstance(v, str):
        return False
    v = v.strip()
    if not v.startswith("0x") or len(v) != 42:
        return False
    try:
        int(v[2:], 16)
    except ValueError:
        return False
    return True


def normalize_address(v: str) -> str:
    if not is_address(v):
        raise ValueError(f"Invalid address: {v!r}")
    return v.strip().lower()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


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
        value = value.strip().strip("'").strip('"')
        if override_existing or key not in os.environ:
            os.environ[key] = value
    return env_path


def resolve_rpc_url(chain: str) -> tuple[str | None, str | None]:
    for env_name in CHAIN_RPC_ENV_CANDIDATES.get(chain, []):
        value = os.environ.get(env_name, "").strip()
        if value:
            return value, env_name
    return None, None


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
        end = start + length * 2
        if end > len(data):
            return None
        return bytes.fromhex(data[start:end]).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None


def decode_abi_address(hex_result: str | None) -> str | None:
    if not isinstance(hex_result, str) or not hex_result:
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < 64:
        return None
    candidate = "0x" + data[-40:]
    return normalize_address(candidate) if is_address(candidate) else None


def extract_deploy_by_chain(raw: Any) -> tuple[Any, dict[str, list[dict[str, Any]]]]:
    if not isinstance(raw, dict):
        return raw, {}
    source = raw["byChain"] if isinstance(raw.get("byChain"), dict) else raw
    out: dict[str, list[dict[str, Any]]] = {}
    for chain, records in source.items():
        if isinstance(chain, str) and isinstance(records, list):
            out[chain] = [r for r in records if isinstance(r, dict)]
    return raw, out


def load_markets_hook_by_chain_and_id(path: Path) -> dict[str, dict[int, str]]:
    data = load_json(path)
    out: dict[str, dict[int, str]] = {}
    if not isinstance(data, dict):
        return out
    for chain, markets in data.items():
        if not isinstance(chain, str) or not isinstance(markets, list):
            continue
        chain_map: dict[int, str] = {}
        for m in markets:
            if not isinstance(m, dict):
                continue
            market_id = m.get("id")
            hook = m.get("hook")
            if isinstance(market_id, int) and is_address(hook):
                chain_map[market_id] = normalize_address(hook)
        out[chain] = chain_map
    return out


def load_sic_by_chain_and_id(path: Path) -> dict[str, dict[int, dict[str, str]]]:
    data = load_json(path)
    out: dict[str, dict[int, dict[str, str]]] = {}
    if not isinstance(data, dict):
        return out

    for chain, obj in data.items():
        if not isinstance(chain, str) or not isinstance(obj, dict):
            continue
        id_map: dict[int, dict[str, str]] = {}
        for key, value in obj.items():
            if not isinstance(key, str) or not is_address(value):
                continue
            id_match = ID_RE.search(key)
            kind_match = KIND_RE.search(key)
            if not id_match or not kind_match:
                continue
            market_id = int(id_match.group(1))
            kind = kind_match.group(1).lower()
            id_map.setdefault(market_id, {})[kind] = normalize_address(value)
        out[chain] = id_map
    return out


def current_gauges_by_kind(record: dict[str, Any]) -> dict[str, str]:
    entries = record.get("entries") if isinstance(record.get("entries"), list) else record.get("gauges")
    if not isinstance(entries, list):
        return {}
    out: dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        gauge = entry.get("gauge")
        share_kind = entry.get("shareTokenKind")
        if not is_address(gauge) or not isinstance(share_kind, str):
            continue
        if share_kind == "collateralShareToken":
            out["collateral"] = normalize_address(gauge)
        elif share_kind == "protectedShareToken":
            out["protected"] = normalize_address(gauge)
        elif share_kind == "debtShareToken":
            out["debt"] = normalize_address(gauge)
    return out


def main() -> int:
    args = parse_args()
    env_path = load_repo_env(override_existing=False)
    if env_path:
        print(f"[info] loaded env from {env_path}")

    deploy_raw, deploy_by_chain = extract_deploy_by_chain(load_json(args.deploy_json))
    hook_by_chain_id = load_markets_hook_by_chain_and_id(args.markets_json)
    sic_by_chain_id = load_sic_by_chain_and_id(args.sic_json)
    chain_filter = {c.strip().lower() for c in args.chain} if args.chain else set()

    planned: list[tuple[str, dict[str, Any], int, dict[str, str], str]] = []

    for chain, records in sorted(deploy_by_chain.items(), key=lambda x: x[0]):
        if chain_filter and chain.lower() not in chain_filter:
            continue
        sic_chain = sic_by_chain_id.get(chain, {})
        for rec in records:
            if rec.get("success") is not False:
                continue
            market_id = rec.get("id")
            if not isinstance(market_id, int):
                continue
            expected = sic_chain.get(market_id)
            if not expected:
                continue
            current = current_gauges_by_kind(rec)
            if current == expected:
                continue
            hook = ""
            entries = rec.get("entries")
            if isinstance(entries, list):
                for e in entries:
                    if isinstance(e, dict) and is_address(e.get("hook")):
                        hook = normalize_address(e["hook"])
                        break
            if not hook:
                hook = hook_by_chain_id.get(chain, {}).get(market_id, "")
            if not is_address(hook):
                print(f"[warn] {chain} id={market_id}: missing hook, skipping sync for this record")
                continue
            planned.append((chain, rec, market_id, expected, normalize_address(hook)))

    if not planned:
        print("[info] no failed records requiring synchronization")
        return 0

    gauges_needed_by_chain: dict[str, set[str]] = {}
    for chain, _rec, _id, expected, _hook in planned:
        gauges_needed_by_chain.setdefault(chain, set()).update(expected.values())

    gauge_meta: dict[str, dict[str, dict[str, str]]] = {}
    rpc_failures = 0
    for chain, gauges_set in sorted(gauges_needed_by_chain.items(), key=lambda x: x[0]):
        rpc_url, rpc_env = resolve_rpc_url(chain)
        if not rpc_url:
            print(f"[warn] {chain}: missing RPC, cannot fetch shareToken/version")
            rpc_failures += 1
            continue
        preflight_err = rpc_preflight(rpc_url, timeout=20)
        if preflight_err:
            print(f"[warn] {chain}: RPC preflight failed ({preflight_err})")
            rpc_failures += 1
            continue
        gauges = sorted(gauges_set)
        calls: list[tuple[str, str]] = []
        for g in gauges:
            calls.append((g, SHARE_TOKEN_SELECTOR))
        results, err = multicall_eth_calls(chain, rpc_url, calls, timeout=120)
        if err:
            print(f"[warn] {chain}: multicall error ({err})")
            rpc_failures += 1
            continue
        chain_meta: dict[str, dict[str, str]] = {}
        for idx, g in enumerate(gauges):
            share_res, share_err = results[idx]
            share_token = decode_abi_address(share_res) if not share_err else None
            chain_meta[g] = {
                "shareToken": share_token or "",
            }
        gauge_meta[chain] = chain_meta
        print(f"[info] {chain}: resolved metadata for {len(chain_meta)} gauges via {rpc_env}")

    changed_records = 0
    changed_entries = 0
    for chain, rec, market_id, expected, hook in planned:
        chain_meta = gauge_meta.get(chain, {})
        existing_by_kind: dict[str, dict[str, Any]] = {}
        existing_entries = rec.get("entries")
        if isinstance(existing_entries, list):
            for entry in existing_entries:
                if not isinstance(entry, dict):
                    continue
                kind = entry.get("shareTokenKind")
                if isinstance(kind, str):
                    existing_by_kind[kind] = entry
        new_entries: list[dict[str, str]] = []
        for kind in ("collateral", "protected", "debt"):
            gauge_addr = expected.get(kind)
            if not gauge_addr:
                continue
            meta = chain_meta.get(gauge_addr, {})
            share_token = meta.get("shareToken", "")
            if not is_address(share_token):
                print(
                    f"[warn] {chain} id={market_id}: missing shareToken for gauge {gauge_addr}, "
                    "keeping previous record unchanged"
                )
                new_entries = []
                break
            share_token_kind = KIND_TO_SHARE_TOKEN_KIND[kind]
            entry_payload: dict[str, str] = {
                "hook": hook,
                "gauge": gauge_addr,
                "shareToken": normalize_address(share_token),
                "shareTokenKind": share_token_kind,
            }
            prev_version = existing_by_kind.get(share_token_kind, {}).get("gaugeVersion")
            if isinstance(prev_version, str) and prev_version.strip():
                entry_payload["gaugeVersion"] = prev_version
            new_entries.append(entry_payload)
        if not new_entries:
            continue
        rec["entries"] = new_entries
        changed_records += 1
        changed_entries += len(new_entries)
        print(f"[ok] synced chain={chain} id={market_id} entries={len(new_entries)}")

    print()
    print(f"Planned failed records: {len(planned)}")
    print(f"Synchronized records: {changed_records}")
    print(f"Synchronized entries: {changed_entries}")
    print(f"RPC failure chains: {rpc_failures}")

    if changed_records == 0:
        return 0

    if args.dry_run:
        print("[info] dry-run enabled, no file written")
        return 0

    save_json(args.deploy_json, deploy_raw)
    print(f"[ok] wrote synchronized deploy data: {args.deploy_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
