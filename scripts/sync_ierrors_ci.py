#!/usr/bin/env python3
"""
Sync IErrors.sol in CI:
- run generator,
- detect newly added custom errors,
- create PR comment body,
- optionally commit & push on pull_request events.

uses Foundry cache to generate IErrors.sol from foundry artifacts.

usage:
    python3 scripts/sync_ierrors_ci.py --commit-on-pr
"""

from __future__ import annotations

import argparse
import json
import os
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


def write_comment(path: Path, new_errors: list[str]) -> None:
    lines = ["Detected new custom errors:", ""]
    lines.extend([f"- `{err}`" for err in new_errors])
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def push_with_retries(branch: str, retries: int) -> tuple[bool, str]:
    last_error = ""
    for _ in range(retries):
        rebase = run_cmd(
            ["git", "pull", "--rebase", "origin", branch],
            check=False,
        )
        if rebase.returncode != 0:
            last_error = rebase.stderr.strip() or rebase.stdout.strip()
            continue

        push = run_cmd(
            ["git", "push", "origin", f"HEAD:{branch}"],
            check=False,
        )
        if push.returncode == 0:
            return True, ""

        last_error = push.stderr.strip() or push.stdout.strip()

    return False, last_error


def write_summary(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync IErrors in CI.")
    parser.add_argument(
        "--summary",
        default="ierrors_sync_summary.json",
        help="Path to JSON summary output file.",
    )
    parser.add_argument(
        "--comment",
        default="ierrors_comment.md",
        help="Path to generated PR comment markdown file.",
    )
    parser.add_argument(
        "--commit-on-pr",
        action="store_true",
        help="Commit and push only when event is pull_request.",
    )
    parser.add_argument(
        "--push-retries",
        type=int,
        default=3,
        help="How many pull --rebase + push retries to attempt.",
    )
    args = parser.parse_args()

    summary_path = (ROOT / args.summary).resolve()
    comment_path = (ROOT / args.comment).resolve()

    before_errors = read_error_lines(IERRORS_PATH)

    run_cmd([sys.executable, str(GENERATOR_PATH)], check=True, capture=False)

    after_errors = read_error_lines(IERRORS_PATH)
    new_errors = sorted(after_errors - before_errors)
    has_changes = git_file_changed(IERRORS_PATH)

    if new_errors:
        write_comment(comment_path, new_errors)
    elif comment_path.exists():
        comment_path.unlink()

    summary: dict[str, Any] = {
        "has_changes": has_changes,
        "new_errors": new_errors,
        "new_errors_count": len(new_errors),
        "committed": False,
        "commit_sha": "",
        "commit_message": "",
        "push_ok": False,
        "push_error": "",
        "event_name": os.environ.get("GITHUB_EVENT_NAME", ""),
    }

    if not has_changes:
        write_summary(summary_path, summary)
        print("IErrors is up to date.")
        return 0

    should_commit = (
        args.commit_on_pr
        and os.environ.get("GITHUB_EVENT_NAME") == "pull_request"
    )

    if not should_commit:
        write_summary(summary_path, summary)
        print("IErrors changed, commit skipped (non-PR event).")
        return 0

    branch = os.environ.get("GITHUB_HEAD_REF", "").strip()
    if not branch:
        summary["push_error"] = "Missing GITHUB_HEAD_REF for pull_request event."
        write_summary(summary_path, summary)
        print(summary["push_error"], file=sys.stderr)
        return 1

    commit_message = "chore: sync IErrors from foundry cache"
    run_cmd(["git", "config", "user.name", "github-actions[bot]"])
    run_cmd(["git", "config", "user.email", "github-actions[bot]@users.noreply.github.com"])
    run_cmd(["git", "add", str(IERRORS_PATH.relative_to(ROOT))])

    commit = run_cmd(
        ["git", "commit", "-m", commit_message],
        check=False,
    )
    if commit.returncode != 0:
        summary["push_error"] = commit.stderr.strip() or commit.stdout.strip()
        write_summary(summary_path, summary)
        print(summary["push_error"], file=sys.stderr)
        return 1

    summary["committed"] = True
    summary["commit_message"] = commit_message
    summary["commit_sha"] = run_cmd(["git", "rev-parse", "HEAD"]).stdout.strip()

    ok, err = push_with_retries(branch=branch, retries=max(1, args.push_retries))
    summary["push_ok"] = ok
    summary["push_error"] = err
    write_summary(summary_path, summary)

    if not ok:
        print(f"Push failed after retries: {err}", file=sys.stderr)
        return 1

    print(f"Pushed commit {summary['commit_sha']} to {branch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
