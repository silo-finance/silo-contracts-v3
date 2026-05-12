#!/usr/bin/env python3
"""
Smoke tests for set-permissioned-liquidation workflow.

Step 1:
- verify all deployment records are marked as success=true
- verify every market has at least 2 gauges (entries)

Step 2:
- verify all gauge addresses from deployment output are present
  in "Set Gauge for Current Markets" bundles
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_DEPLOY_GAUGES_PATH = SCRIPT_DIR / "permissioned_liquidation_deploy_gauges_by_chain.json"
DEFAULT_SET_GAUGE_DIR = SCRIPT_DIR / "out"
SET_GAUGE_FILE_RE = re.compile(r"^Set Gauge for Current Markets - .*\.json$")


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
    return parser.parse_args()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


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


def run_step_1(deploy_gauges_path: Path) -> int:
    raw = load_json(deploy_gauges_path)
    by_chain = extract_by_chain(raw)
    if not by_chain:
        print(f"[FAIL] could not read chain records from {deploy_gauges_path}")
        return 1

    total = 0
    failed = 0

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

    print(
        f"[STEP 2] checking gauge coverage in {set_gauge_dir} "
        f"(files matched: {file_count})"
    )

    missing_total = 0
    expected_total = 0
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

    print()
    print(f"Expected gauge addresses: {expected_total}")
    print(f"Missing gauge addresses: {missing_total}")
    if missing_total == 0:
        print("[OK] Step 2 passed")
        return 0

    print("[FAIL] Step 2 failed")
    return 1


def main() -> int:
    args = parse_args()
    step_1_rc = run_step_1(args.deploy_gauges_json)
    print()
    step_2_rc = run_step_2(args.deploy_gauges_json, args.set_gauge_dir)
    return 0 if step_1_rc == 0 and step_2_rc == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
