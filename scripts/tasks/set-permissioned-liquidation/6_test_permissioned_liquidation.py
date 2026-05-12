#!/usr/bin/env python3
"""
Smoke tests for set-permissioned-liquidation workflow.

Step 1:
- verify all deployment records are marked as success=true
- verify every market has at least 2 gauges (entries)

Step 2:
- verify all gauge addresses from deployment output are present
  in "Set Gauge for Current Markets" bundles

Step 4:
- if gaugeVersion exists, it must equal expected value

Step 5:
- verify gauge SHARE_TOKEN() against market share tokens from SiloConfig
"""

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

DEFAULT_DEPLOY_GAUGES_PATH = SCRIPT_DIR / "permissioned_liquidation_deploy_gauges_by_chain.json"
DEFAULT_SET_GAUGE_DIR = SCRIPT_DIR / "out"
SET_GAUGE_FILE_RE = re.compile(r"^Set Gauge for Current Markets - .*\.json$")
VERSION_SELECTOR = "0xffa1ad74"
GET_SILOS_SELECTOR = "0xaecc90cb"
GET_SHARE_TOKENS_SELECTOR = "0x483b24f0"
SHARE_TOKEN_SELECTOR = "0x1d7e3556"
DEFAULT_EXPECTED_GAUGE_VERSION = "PermissionedLiquidationController 4.17.0"

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
    parser = argparse.ArgumentParser(
        description=(
            "Step 1 validation for permissioned liquidation deployment output "
            "(success=true and minimum 2 gauges per market)."
        )
    )
    parser.add_argument(
        "--deploy-gauges-json",
        type=Path,
        default=DEFAULT_DEPLOY_GAUGES_PATH,
        help=f"Path to deploy gauges JSON (default: {DEFAULT_DEPLOY_GAUGES_PATH})",
    )
    parser.add_argument(
        "--set-gauge-dir",
        type=Path,
        default=DEFAULT_SET_GAUGE_DIR,
        help=f'Directory with "Set Gauge for Current Markets" JSON files (default: {DEFAULT_SET_GAUGE_DIR})',
    )
    parser.add_argument(
        "--skip-version-update",
        action="store_true",
        help="Skip step 3 (fetch gauge versions and update deploy JSON).",
    )
    parser.add_argument(
        "--expected-gauge-version",
        default=DEFAULT_EXPECTED_GAUGE_VERSION,
        help=(
            "Expected gaugeVersion value for validation step "
            f"(default: {DEFAULT_EXPECTED_GAUGE_VERSION})"
        ),
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def extract_by_chain(raw: Any) -> dict[str, list[dict[str, Any]]]:
    if isinstance(raw, dict) and isinstance(raw.get("byChain"), dict):
        source = raw["byChain"]
    elif isinstance(raw, dict):
        source = raw
    else:
        return {}

    out: dict[str, list[dict[str, Any]]] = {}
    for chain, items in source.items():
        if isinstance(chain, str) and isinstance(items, list):
            out[chain] = [i for i in items if isinstance(i, dict)]
    return out


def record_entries_count(record: dict[str, Any]) -> int:
    if isinstance(record.get("entries"), list):
        return len(record["entries"])
    if isinstance(record.get("gauges"), list):
        return len(record["gauges"])
    return 0


def is_address(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    value = value.strip()
    if not value.startswith("0x") or len(value) != 42:
        return False
    try:
        int(value[2:], 16)
    except ValueError:
        return False
    return True


def normalize_address(value: str) -> str:
    if not is_address(value):
        raise ValueError(f"Invalid address: {value!r}")
    return value.strip().lower()


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
        end = start + (length * 2)
        if end > len(data):
            return None
        return bytes.fromhex(data[start:end]).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None


def decode_abi_addresses(hex_result: str | None, expected_count: int) -> list[str] | None:
    if not isinstance(hex_result, str) or not hex_result:
        return None
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < expected_count * 64:
        return None
    out: list[str] = []
    for i in range(expected_count):
        chunk = data[i * 64 : (i + 1) * 64]
        candidate = "0x" + chunk[-40:]
        if not is_address(candidate):
            return None
        out.append(normalize_address(candidate))
    return out


def encode_address_arg(addr: str) -> str:
    normalized = normalize_address(addr)[2:]
    return "0" * 24 + normalized


def _chunks(items: list[str], size: int) -> list[list[str]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def run_step_1(deploy_gauges_path: Path) -> int:
    raw = load_json(deploy_gauges_path)
    by_chain = extract_by_chain(raw)
    if not by_chain:
        print(f"[FAIL] could not read chain records from {deploy_gauges_path}")
        return 1

    total = 0
    failed = 0
    marked_false = 0

    print(f"[STEP 1] validating {deploy_gauges_path}")

    for chain in sorted(by_chain):
        records = by_chain[chain]
        for rec in records:
            total += 1
            market_id = rec.get("id")
            silo_config = str(rec.get("siloConfig") or "").lower()
            success_ok = rec.get("success") is True
            entries_count = record_entries_count(rec)
            entries_ok = entries_count >= 2

            if success_ok and entries_ok:
                continue

            failed += 1
            if rec.get("success") is not False:
                rec["success"] = False
                marked_false += 1
            reasons: list[str] = []
            if not success_ok:
                reasons.append(f"success={rec.get('success')!r}")
            if not entries_ok:
                reasons.append(f"gauges={entries_count} (<2)")
            print(
                f"[FAIL] chain={chain} id={market_id} siloConfig={silo_config or '-'} "
                + " | ".join(reasons)
            )

    passed = total - failed
    print()
    print(f"Checked records: {total}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    if marked_false > 0:
        save_json(deploy_gauges_path, raw)
        print(f"Records marked success=false: {marked_false}")

    if failed == 0:
        print("[OK] Step 1 passed")
        return 0

    print("[FAIL] Step 1 failed")
    return 1


def gauges_expected_by_chain(by_chain: dict[str, list[dict[str, Any]]]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for chain, records in by_chain.items():
        chain_set: set[str] = set()
        for rec in records:
            if rec.get("success") is not True:
                continue
            entries = rec.get("entries") if isinstance(rec.get("entries"), list) else rec.get("gauges")
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                gauge = entry.get("gauge")
                if is_address(gauge):
                    chain_set.add(normalize_address(gauge))
        out[chain] = chain_set
    return out


def detect_chain_name_from_bundle(bundle: dict[str, Any], filename: str) -> str | None:
    meta = bundle.get("meta")
    if isinstance(meta, dict):
        name = meta.get("name")
        prefix = "Set Gauge for Current Markets - "
        if isinstance(name, str) and name.startswith(prefix):
            chain = name[len(prefix) :].strip()
            if chain:
                return chain

    stem = Path(filename).stem
    prefix = "Set Gauge for Current Markets - "
    if stem.startswith(prefix):
        # fallback for unexpected files, best effort:
        # "Set Gauge for Current Markets - arbitrum_one - 0xaad220fa"
        rest = stem[len(prefix) :].strip()
        if " - 0x" in rest:
            return rest.split(" - 0x", 1)[0].strip()
        return rest
    return None


def gauges_found_in_set_gauge_files(set_gauge_dir: Path) -> tuple[dict[str, set[str]], int]:
    if not set_gauge_dir.exists() or not set_gauge_dir.is_dir():
        raise FileNotFoundError(f"Set gauge directory not found: {set_gauge_dir}")

    files = [
        p
        for p in sorted(set_gauge_dir.iterdir(), key=lambda x: x.name.lower())
        if p.is_file() and SET_GAUGE_FILE_RE.match(p.name)
    ]
    found: dict[str, set[str]] = {}
    for path in files:
        raw = load_json(path)
        if not isinstance(raw, dict):
            continue
        chain = detect_chain_name_from_bundle(raw, path.name)
        if not chain:
            continue
        transactions = raw.get("transactions")
        if not isinstance(transactions, list):
            continue
        chain_set = found.setdefault(chain, set())
        for tx in transactions:
            if not isinstance(tx, dict):
                continue
            civ = tx.get("contractInputsValues")
            if not isinstance(civ, dict):
                continue
            gauge = civ.get("_gauge")
            if is_address(gauge):
                chain_set.add(normalize_address(gauge))
    return found, len(files)


def run_step_2(deploy_gauges_path: Path, set_gauge_dir: Path) -> int:
    raw = load_json(deploy_gauges_path)
    by_chain = extract_by_chain(raw)
    if not by_chain:
        print(f"[FAIL] could not read chain records from {deploy_gauges_path}")
        return 1

    expected = gauges_expected_by_chain(by_chain)
    found, file_count = gauges_found_in_set_gauge_files(set_gauge_dir)
    gauge_to_records_by_chain: dict[str, dict[str, list[dict[str, Any]]]] = {}
    for chain, records in by_chain.items():
        chain_map: dict[str, list[dict[str, Any]]] = {}
        for rec in records:
            entries_obj = rec.get("entries")
            if not isinstance(entries_obj, list):
                entries_obj = rec.get("gauges")
            if not isinstance(entries_obj, list):
                continue
            for entry in entries_obj:
                if not isinstance(entry, dict):
                    continue
                gauge = entry.get("gauge")
                if not is_address(gauge):
                    continue
                chain_map.setdefault(normalize_address(gauge), []).append(rec)
        gauge_to_records_by_chain[chain] = chain_map

    print(
        f"[STEP 2] checking gauge coverage in {set_gauge_dir} "
        f"(files matched: {file_count})"
    )

    missing_total = 0
    expected_total = 0
    marked_false = 0
    for chain in sorted(expected):
        expected_chain = expected[chain]
        found_chain = found.get(chain, set())
        expected_total += len(expected_chain)
        missing = sorted(expected_chain - found_chain)
        if not missing:
            continue
        missing_total += len(missing)
        print(f"[FAIL] chain={chain} missing gauges: {len(missing)}")
        for gauge in missing:
            print(f"  - {gauge}")
            for rec in gauge_to_records_by_chain.get(chain, {}).get(gauge, []):
                if rec.get("success") is not False:
                    rec["success"] = False
                    marked_false += 1

    print()
    print(f"Expected gauge addresses: {expected_total}")
    print(f"Missing gauge addresses: {missing_total}")
    if marked_false > 0:
        save_json(deploy_gauges_path, raw)
        print(f"Records marked success=false: {marked_false}")
    if missing_total == 0:
        print("[OK] Step 2 passed")
        return 0

    print("[FAIL] Step 2 failed")
    return 1


def run_step_3_update_gauge_versions(deploy_gauges_path: Path) -> int:
    raw = load_json(deploy_gauges_path)
    by_chain = extract_by_chain(raw)
    if not by_chain:
        print(f"[FAIL] could not read chain records from {deploy_gauges_path}")
        return 1

    print("[STEP 3] fetch gauge versions via multicall and update deploy JSON")
    total_gauges = 0
    already_with_version = 0
    updated = 0
    chain_failures = 0

    for chain in sorted(by_chain):
        records = by_chain[chain]
        gauge_to_entries: dict[str, list[dict[str, Any]]] = {}
        for rec in records:
            entries_obj = rec.get("entries")
            if not isinstance(entries_obj, list):
                entries_obj = rec.get("gauges")
            if not isinstance(entries_obj, list):
                continue
            for entry in entries_obj:
                if not isinstance(entry, dict):
                    continue
                gauge = entry.get("gauge")
                if not is_address(gauge):
                    continue
                total_gauges += 1
                version = entry.get("gaugeVersion")
                if isinstance(version, str) and version.strip():
                    already_with_version += 1
                    continue
                gauge_n = normalize_address(gauge)
                gauge_to_entries.setdefault(gauge_n, []).append(entry)

        if not gauge_to_entries:
            print(f"[info] {chain}: all gauges already have versions")
            continue

        rpc_url, rpc_env = resolve_rpc_url(chain)
        if not rpc_url:
            print(f"[FAIL] {chain}: missing RPC env (expected one of {CHAIN_RPC_ENV_CANDIDATES.get(chain, [])})")
            chain_failures += 1
            continue

        preflight_err = rpc_preflight(rpc_url, timeout=20)
        if preflight_err:
            print(f"[FAIL] {chain}: RPC preflight failed ({preflight_err})")
            chain_failures += 1
            continue

        gauges = sorted(gauge_to_entries.keys())
        print(
            f"[info] {chain}: fetching versions for {len(gauges)} gauges "
            f"using {rpc_env}"
        )

        for gauges_chunk in _chunks(gauges, 200):
            calls = [(gauge_addr, VERSION_SELECTOR) for gauge_addr in gauges_chunk]
            results, global_err = multicall_eth_calls(chain, rpc_url, calls, timeout=120)
            if global_err:
                print(f"[FAIL] {chain}: multicall failed ({global_err})")
                chain_failures += 1
                # Preserve resumability of step 3: mark chunk gauges as legacy.
                for gauge_addr in gauges_chunk:
                    for entry in gauge_to_entries[gauge_addr]:
                        entry["gaugeVersion"] = "legacy"
                        updated += 1
                continue

            for gauge_addr, (hex_result, call_err) in zip(gauges_chunk, results):
                if call_err:
                    decoded_version = "legacy"
                else:
                    decoded = decode_abi_string(hex_result)
                    decoded_version = decoded.strip() if isinstance(decoded, str) and decoded.strip() else "legacy"
                for entry in gauge_to_entries[gauge_addr]:
                    entry["gaugeVersion"] = decoded_version
                    updated += 1

    if updated > 0:
        save_json(deploy_gauges_path, raw)
        print(f"[OK] updated {updated} entries with gaugeVersion in {deploy_gauges_path}")
    else:
        print("[info] no gaugeVersion updates were necessary")

    print()
    print(f"Gauge entries scanned: {total_gauges}")
    print(f"Already had gaugeVersion: {already_with_version}")
    print(f"GaugeVersion updated now: {updated}")
    print(f"Chains with RPC/multicall failures: {chain_failures}")

    if chain_failures == 0:
        print("[OK] Step 3 passed")
        return 0

    print("[FAIL] Step 3 completed with chain failures")
    return 1


def run_step_4_validate_gauge_version(
    deploy_gauges_path: Path, *, expected_version: str
) -> int:
    raw = load_json(deploy_gauges_path)
    by_chain = extract_by_chain(raw)
    if not by_chain:
        print(f"[FAIL] could not read chain records from {deploy_gauges_path}")
        return 1

    print(f"[STEP 4] validate gaugeVersion == {expected_version!r}")
    checked = 0
    mismatches = 0
    missing = 0
    marked_false = 0
    marked_true = 0

    for chain in sorted(by_chain):
        for rec in by_chain[chain]:
            market_id = rec.get("id")
            entries_obj = rec.get("entries")
            if not isinstance(entries_obj, list):
                entries_obj = rec.get("gauges")
            if not isinstance(entries_obj, list):
                continue

            record_has_error = False
            record_version_checks = 0
            for entry in entries_obj:
                if not isinstance(entry, dict):
                    continue
                gauge = entry.get("gauge")
                if not is_address(gauge):
                    continue
                version = entry.get("gaugeVersion")
                if not isinstance(version, str) or not version.strip():
                    missing += 1
                    record_has_error = True
                    if rec.get("success") is not False:
                        rec["success"] = False
                        marked_false += 1
                    continue

                checked += 1
                record_version_checks += 1
                version_norm = version.strip()
                if version_norm != expected_version:
                    mismatches += 1
                    record_has_error = True
                    if rec.get("success") is not False:
                        rec["success"] = False
                        marked_false += 1
                    print(
                        f"[FAIL] chain={chain} id={market_id} gauge={normalize_address(gauge)} "
                        f"gaugeVersion={version_norm!r}"
                    )

            # Recovery path: when all gauge versions for this record are valid,
            # allow success to become true again.
            if not record_has_error and record_version_checks > 0 and rec.get("success") is False:
                rec["success"] = True
                marked_true += 1

    print()
    print(f"Gauge entries with gaugeVersion present: {checked}")
    print(f"Gauge entries with missing gaugeVersion: {missing}")
    print(f"Gauge version mismatches: {mismatches}")
    if marked_false > 0 or marked_true > 0:
        save_json(deploy_gauges_path, raw)
        if marked_false > 0:
            print(f"Records marked success=false: {marked_false}")
        if marked_true > 0:
            print(f"Records marked success=true: {marked_true}")
    if mismatches == 0 and missing == 0:
        print("[OK] Step 4 passed")
        return 0

    print("[FAIL] Step 4 failed")
    return 1


def run_step_5_validate_gauge_share_token(deploy_gauges_path: Path) -> int:
    raw = load_json(deploy_gauges_path)
    by_chain = extract_by_chain(raw)
    if not by_chain:
        print(f"[FAIL] could not read chain records from {deploy_gauges_path}")
        return 1

    print("[STEP 5] validate gauge SHARE_TOKEN against market share tokens")
    total_entries_checked = 0
    mismatches = 0
    marked_false = 0
    marked_true = 0
    overwritten_error = 0
    rpc_failures = 0

    for chain in sorted(by_chain):
        records = by_chain[chain]
        rpc_url, rpc_env = resolve_rpc_url(chain)
        if not rpc_url:
            print(f"[FAIL] {chain}: missing RPC env")
            rpc_failures += 1
            continue
        preflight_err = rpc_preflight(rpc_url, timeout=20)
        if preflight_err:
            print(f"[FAIL] {chain}: RPC preflight failed ({preflight_err})")
            rpc_failures += 1
            continue

        cfgs = sorted(
            {
                normalize_address(rec["siloConfig"])
                for rec in records
                if isinstance(rec.get("siloConfig"), str) and is_address(rec["siloConfig"])
            }
        )

        cfg_to_silos: dict[str, tuple[str, str]] = {}
        if cfgs:
            cfg_calls = [(cfg, GET_SILOS_SELECTOR) for cfg in cfgs]
            cfg_results, cfg_err = multicall_eth_calls(chain, rpc_url, cfg_calls, timeout=120)
            if cfg_err:
                print(f"[FAIL] {chain}: multicall getSilos failed ({cfg_err})")
                rpc_failures += 1
            else:
                for cfg, (res, err) in zip(cfgs, cfg_results):
                    if err:
                        continue
                    decoded = decode_abi_addresses(res, 2)
                    if decoded is None:
                        continue
                    cfg_to_silos[cfg] = (decoded[0], decoded[1])

        cfg_silo_to_share_tokens: dict[tuple[str, str], tuple[str, str, str]] = {}
        cfg_silo_pairs: list[tuple[str, str]] = []
        for cfg, (silo0, silo1) in cfg_to_silos.items():
            cfg_silo_pairs.append((cfg, silo0))
            cfg_silo_pairs.append((cfg, silo1))
        if cfg_silo_pairs:
            silo_calls = [(cfg, GET_SHARE_TOKENS_SELECTOR + encode_address_arg(silo)) for cfg, silo in cfg_silo_pairs]
            silo_results, silo_err = multicall_eth_calls(chain, rpc_url, silo_calls, timeout=120)
            if silo_err:
                print(f"[FAIL] {chain}: multicall getShareTokens failed ({silo_err})")
                rpc_failures += 1
            else:
                for (cfg, silo), (res, err) in zip(cfg_silo_pairs, silo_results):
                    if err:
                        continue
                    decoded = decode_abi_addresses(res, 3)
                    if decoded is None:
                        continue
                    # (protected, collateral, debt)
                    cfg_silo_to_share_tokens[(cfg, silo)] = (decoded[0], decoded[1], decoded[2])

        gauges = sorted(
            {
                normalize_address(entry["gauge"])
                for rec in records
                for entry in (rec.get("entries") if isinstance(rec.get("entries"), list) else [])
                if isinstance(entry, dict) and isinstance(entry.get("gauge"), str) and is_address(entry["gauge"])
            }
        )
        gauge_to_share_token: dict[str, str] = {}
        if gauges:
            gauge_calls = [(g, SHARE_TOKEN_SELECTOR) for g in gauges]
            gauge_results, gauge_err = multicall_eth_calls(chain, rpc_url, gauge_calls, timeout=120)
            if gauge_err:
                print(f"[FAIL] {chain}: multicall SHARE_TOKEN failed ({gauge_err})")
                rpc_failures += 1
            else:
                for gauge, (res, err) in zip(gauges, gauge_results):
                    if err:
                        continue
                    decoded = decode_abi_addresses(res, 1)
                    if decoded is None:
                        continue
                    gauge_to_share_token[gauge] = decoded[0]

        for rec in records:
            cfg = rec.get("siloConfig")
            if not isinstance(cfg, str) or not is_address(cfg):
                continue
            cfg_n = normalize_address(cfg)
            silos_pair = cfg_to_silos.get(cfg_n)
            if not silos_pair:
                rec["success"] = False
                rec["error"] = "cfg_silos_read_failed"
                marked_false += 1
                overwritten_error += 1
                mismatches += 1
                continue

            share0 = cfg_silo_to_share_tokens.get((cfg_n, silos_pair[0]))
            share1 = cfg_silo_to_share_tokens.get((cfg_n, silos_pair[1]))
            if not share0 or not share1:
                rec["success"] = False
                rec["error"] = "cfg_share_tokens_read_failed"
                marked_false += 1
                overwritten_error += 1
                mismatches += 1
                continue

            # interested in protected+collateral from both silos
            allowed = {share0[0], share0[1], share1[0], share1[1]}
            entries_obj = rec.get("entries")
            if not isinstance(entries_obj, list):
                continue

            record_has_error = False
            record_checked = False
            for entry in entries_obj:
                if not isinstance(entry, dict):
                    continue
                gauge = entry.get("gauge")
                recorded_share = entry.get("shareToken")
                if not isinstance(gauge, str) or not is_address(gauge):
                    continue
                if not isinstance(recorded_share, str) or not is_address(recorded_share):
                    continue
                record_checked = True
                total_entries_checked += 1
                gauge_n = normalize_address(gauge)
                recorded_share_n = normalize_address(recorded_share)
                gauge_share = gauge_to_share_token.get(gauge_n)
                if not gauge_share:
                    record_has_error = True
                    rec["error"] = "gauge_share_token_read_failed"
                    continue
                if gauge_share not in allowed:
                    record_has_error = True
                    rec["error"] = "gauge_share_token_not_in_market"
                    continue
                if recorded_share_n != gauge_share:
                    record_has_error = True
                    rec["error"] = "json_share_token_mismatch"
                    continue

            if record_has_error:
                if rec.get("success") is not False:
                    marked_false += 1
                rec["success"] = False
                overwritten_error += 1
                mismatches += 1
            elif record_checked and rec.get("success") is False:
                rec["success"] = True
                marked_true += 1
                # keep existing error message untouched; other checks may still use it

    if marked_false > 0 or overwritten_error > 0 or marked_true > 0:
        save_json(deploy_gauges_path, raw)

    print()
    print(f"Checked gauge entries: {total_entries_checked}")
    print(f"Mismatched records: {mismatches}")
    print(f"Records marked success=false: {marked_false}")
    print(f"Records marked success=true: {marked_true}")
    print(f"Errors overwritten: {overwritten_error}")
    print(f"RPC failure chains: {rpc_failures}")

    if mismatches == 0 and rpc_failures == 0:
        print("[OK] Step 5 passed")
        return 0

    print("[FAIL] Step 5 failed")
    return 1


def main() -> int:
    args = parse_args()
    env_path = load_repo_env(override_existing=False)
    if env_path:
        print(f"[info] loaded env from {env_path}")

    step_1_rc = run_step_1(args.deploy_gauges_json)
    print()
    step_2_rc = run_step_2(args.deploy_gauges_json, args.set_gauge_dir)
    print()
    if args.skip_version_update:
        print("[info] step 3 skipped (--skip-version-update)")
        step_3_rc = 0
    else:
        step_3_rc = run_step_3_update_gauge_versions(args.deploy_gauges_json)
    print()
    step_4_rc = run_step_4_validate_gauge_version(
        args.deploy_gauges_json,
        expected_version=args.expected_gauge_version,
    )
    print()
    step_5_rc = run_step_5_validate_gauge_share_token(args.deploy_gauges_json)
    return (
        0
        if step_1_rc == 0 and step_2_rc == 0 and step_3_rc == 0 and step_4_rc == 0 and step_5_rc == 0
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
