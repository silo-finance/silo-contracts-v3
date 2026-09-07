#!/usr/bin/env python3
"""
Convert the loss list JSON (`out/losses.json`) into a semicolon-separated CSV
(`out/losses.csv`) with one row per depositor.

Field separator is ';' (semicolon). All amounts are raw integer strings.

    python3 scripts/tasks/silo-vault-loss-list/to_csv.py
    python3 scripts/tasks/silo-vault-loss-list/to_csv.py --json path/to/losses.json --csv path/to/out.csv
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_JSON = SCRIPT_DIR / "out" / "losses.json"
DEFAULT_CSV = SCRIPT_DIR / "out" / "losses.csv"

COLUMNS = ["address", "shares", "value_before", "value_after", "loss_previewdiff", "loss_analytic"]


def write_csv(json_path: Path, csv_path: Path) -> int:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    depositors = data.get("depositors", [])

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS, delimiter=";", extrasaction="ignore")
        writer.writeheader()
        for row in depositors:
            writer.writerow({key: row.get(key, "") for key in COLUMNS})
    print(f"[ok] wrote {csv_path} ({len(depositors)} rows)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert losses.json to a semicolon-separated CSV.")
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON, help=f"Input JSON (default: {DEFAULT_JSON})")
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV, help=f"Output CSV (default: {DEFAULT_CSV})")
    args = parser.parse_args()
    if not args.json.exists():
        raise SystemExit(f"Input JSON not found: {args.json}. Run snapshot_losses.py first.")
    return write_csv(args.json, args.csv)


if __name__ == "__main__":
    raise SystemExit(main())
