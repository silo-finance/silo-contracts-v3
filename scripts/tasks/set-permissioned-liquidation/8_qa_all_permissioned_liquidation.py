#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent

DEFAULT_MARKETS_JSON = SCRIPT_DIR / "v3_markets_by_chain.json"
DEFAULT_DEPLOY_JSON = SCRIPT_DIR / "permissioned_liquidation_deploy_gauges_by_chain.json"
DEFAULT_SET_GAUGE_DIR = SCRIPT_DIR / "out"
SET_GAUGE_FILE_RE = re.compile(r"^Set Gauge for Current Markets - .*\.json$")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Step 8 QA for permissioned liquidation workflow.")
    p.add_argument("--markets-json", type=Path, default=DEFAULT_MARKETS_JSON)
    p.add_argument("--deploy-json", type=Path, default=DEFAULT_DEPLOY_JSON)
    p.add_argument("--set-gauge-dir", type=Path, default=DEFAULT_SET_GAUGE_DIR)
    p.add_argument("--chain", action="append", default=[], help="Optional chain filter (repeatable).")
    return p.parse_args()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


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


def extract_deploy_by_chain(raw: Any) -> dict[str, list[dict[str, Any]]]:
    if not isinstance(raw, dict):
        return {}
    source = raw["byChain"] if isinstance(raw.get("byChain"), dict) else raw
    out: dict[str, list[dict[str, Any]]] = {}
    for chain, records in source.items():
        if isinstance(chain, str) and isinstance(records, list):
            out[chain] = [r for r in records if isinstance(r, dict)]
    return out


def expected_markets_from_v3(path: Path) -> dict[str, set[str]]:
    data = load_json(path)
    if not isinstance(data, dict):
        return {}
    out: dict[str, set[str]] = {}
    for chain, markets in data.items():
        if not isinstance(chain, str) or not isinstance(markets, list):
            continue
        chain_set: set[str] = set()
        for m in markets:
            if not isinstance(m, dict):
                continue
            addr = m.get("address")
            if is_address(addr):
                chain_set.add(normalize_address(addr))
        out[chain] = chain_set
    return out


def deployed_markets(path: Path) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    data = extract_deploy_by_chain(load_json(path))
    markets_by_chain: dict[str, set[str]] = {}
    gauges_by_chain: dict[str, set[str]] = {}
    for chain, records in data.items():
        mset: set[str] = set()
        gset: set[str] = set()
        for rec in records:
            cfg = rec.get("siloConfig")
            if is_address(cfg):
                mset.add(normalize_address(cfg))
            entries = rec.get("entries") if isinstance(rec.get("entries"), list) else rec.get("gauges")
            if not isinstance(entries, list):
                continue
            for e in entries:
                if not isinstance(e, dict):
                    continue
                gauge = e.get("gauge")
                if is_address(gauge):
                    gset.add(normalize_address(gauge))
        markets_by_chain[chain] = mset
        gauges_by_chain[chain] = gset
    return markets_by_chain, gauges_by_chain


def detect_chain_name_from_bundle(bundle: dict[str, Any], filename: str) -> str | None:
    meta = bundle.get("meta")
    prefix = "Set Gauge for Current Markets - "
    if isinstance(meta, dict):
        name = meta.get("name")
        if isinstance(name, str) and name.startswith(prefix):
            chain = name[len(prefix) :].strip()
            if chain:
                return chain
    stem = Path(filename).stem
    if stem.startswith(prefix):
        rest = stem[len(prefix) :].strip()
        if " - 0x" in rest:
            return rest.split(" - 0x", 1)[0].strip()
        return rest
    return None


def gauges_from_set_gauge_files(set_gauge_dir: Path) -> tuple[dict[str, set[str]], int]:
    if not set_gauge_dir.exists() or not set_gauge_dir.is_dir():
        raise FileNotFoundError(f"Missing set-gauge output dir: {set_gauge_dir}")

    out: dict[str, set[str]] = {}
    matched_files = 0
    for path in sorted(set_gauge_dir.iterdir(), key=lambda p: p.name.lower()):
        if not path.is_file() or not SET_GAUGE_FILE_RE.match(path.name):
            continue
        matched_files += 1
        raw = load_json(path)
        if not isinstance(raw, dict):
            continue
        chain = detect_chain_name_from_bundle(raw, path.name)
        if not chain:
            continue
        txs = raw.get("transactions")
        if not isinstance(txs, list):
            continue
        chain_set = out.setdefault(chain, set())
        for tx in txs:
            if not isinstance(tx, dict):
                continue
            civ = tx.get("contractInputsValues")
            if not isinstance(civ, dict):
                continue
            gauge = civ.get("_gauge")
            if is_address(gauge):
                chain_set.add(normalize_address(gauge))
    return out, matched_files


def main() -> int:
    args = parse_args()
    chain_filter = {c.strip().lower() for c in args.chain} if args.chain else set()

    v3_expected = expected_markets_from_v3(args.markets_json)
    deploy_markets, deploy_gauges = deployed_markets(args.deploy_json)
    set_gauge_gauges, matched_files = gauges_from_set_gauge_files(args.set_gauge_dir)

    all_chains = sorted(set(v3_expected.keys()) | set(deploy_markets.keys()) | set(set_gauge_gauges.keys()))
    if chain_filter:
        all_chains = [c for c in all_chains if c.lower() in chain_filter]

    print("[CHECK 1] Every v3 market exists in permissioned_liquidation_deploy_gauges_by_chain")
    missing_markets = 0
    expected_markets_total = 0
    for chain in all_chains:
        expected = v3_expected.get(chain, set())
        present = deploy_markets.get(chain, set())
        expected_markets_total += len(expected)
        missing = sorted(expected - present)
        if not missing:
            continue
        missing_markets += len(missing)
        print(f"[FAIL] chain={chain} missing markets: {len(missing)}")
        for m in missing:
            print(f"  - {m}")

    print()
    print("[CHECK 2] Every deployed gauge exists in Set Gauge for Current Markets outputs")
    missing_gauges = 0
    expected_gauges_total = 0
    for chain in all_chains:
        expected = deploy_gauges.get(chain, set())
        present = set_gauge_gauges.get(chain, set())
        expected_gauges_total += len(expected)
        missing = sorted(expected - present)
        if not missing:
            continue
        missing_gauges += len(missing)
        print(f"[FAIL] chain={chain} missing gauges in outputs: {len(missing)}")
        for g in missing:
            print(f"  - {g}")

    print()
    print(f"Matched Set Gauge files: {matched_files}")
    print(f"Expected v3 markets: {expected_markets_total}")
    print(f"Missing markets: {missing_markets}")
    print(f"Expected deployed gauges: {expected_gauges_total}")
    print(f"Missing gauges in outputs: {missing_gauges}")

    if missing_markets == 0 and missing_gauges == 0:
        print("[OK] Step 8 QA passed")
        return 0

    print("[FAIL] Step 8 QA failed")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
