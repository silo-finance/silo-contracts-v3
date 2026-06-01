#!/usr/bin/env python3
"""
Validate IErrors.sol in CI:
- run generator,
- detect newly added custom errors,
- fail CI when IErrors.sol is out of date.

Uses Foundry cache to generate IErrors.sol from foundry artifacts.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
IERRORS_PATH = ROOT / "common" / "utils" / "interfaces" / "IErrors.sol"
GENERATOR_PATH = ROOT / "scripts" / "generate_ierrors_from_foundry_cache.py"

ERROR_LINE_RE = re.compile(r"^\s*error\s+.+;\s*$")


def run_cmd(
    args: list[str],
    *,
    check: bool = True,
    capture: bool = True,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd or ROOT),
        text=True,
        capture_output=capture,
        check=check,
    )


def read_error_lines(path: Path) -> set[str]:
    if not path.exists():
        return set()
    lines = path.read_text(encoding="utf-8").splitlines()
    return {line.strip() for line in lines if ERROR_LINE_RE.match(line)}


def git_file_changed(path: Path) -> bool:
    rel = str(path.relative_to(ROOT))
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", rel],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=False,
    )
    return bool(result.stdout.strip())


def write_summary(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def print_failure_instructions(new_errors: list[str]) -> None:
    print("")
    print("Detected custom errors mismatch: common/utils/interfaces/IErrors.sol is out of date.")
    print("Detected new custom errors:")
    if new_errors:
        for err in new_errors:
            print(f"- {err}")
    else:
        print("- (none listed; file changed due to ordering/removal/normalization)")
    print("")
    print("How to fix:")
    print("1) Run: python3 scripts/generate_ierrors_from_foundry_cache.py")
    print("2) Commit updated file: common/utils/interfaces/IErrors.sol")
    print("3) Push changes to this branch")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate IErrors in CI.")
    parser.add_argument(
        "--summary",
        default="ierrors_sync_summary.json",
        help="Path to JSON summary output file.",
    )
    args = parser.parse_args()

    summary_path = (ROOT / args.summary).resolve()

    before_errors = read_error_lines(IERRORS_PATH)

    run_cmd([sys.executable, str(GENERATOR_PATH)], check=True, capture=False)

    after_errors = read_error_lines(IERRORS_PATH)
    new_errors = sorted(after_errors - before_errors)
    has_changes = git_file_changed(IERRORS_PATH)

    summary: dict[str, Any] = {
        "has_changes": has_changes,
        "new_errors": new_errors,
        "new_errors_count": len(new_errors),
    }

    if not has_changes:
        write_summary(summary_path, summary)
        print("IErrors is up to date. No custom errors changes detected.")
        return 0

    if not new_errors:
        write_summary(summary_path, summary)
        print(
            "IErrors changed, but no new custom errors were detected "
            "(only removal/normalization/reordering)."
        )
        return 0

    write_summary(summary_path, summary)
    print_failure_instructions(new_errors)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
