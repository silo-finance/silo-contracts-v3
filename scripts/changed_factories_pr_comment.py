#!/usr/bin/env python3
"""
Detect changed factory deployment files between two git refs and optionally
output a PR comment body.

Used by CI to post a single (editable) comment on PRs when any factory
deployments change (silo-core, silo-vaults, silo-oracles). Contract names are listed
without addresses; CC users can be included.

Usage:
  # List changed factory contract names (one per line)
  python3 scripts/changed_factories_pr_comment.py --base origin/master --head HEAD

  # Output full markdown comment body to a file for sticky-pull-request-comment
  python3 scripts/changed_factories_pr_comment.py --base origin/master --head HEAD --format comment > comment.md

  # In CI: base = github.event.pull_request.base.sha, head = github.sha
  python3 scripts/changed_factories_pr_comment.py --base $BASE_SHA --head $HEAD_SHA --format comment
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Deployment roots we consider for "factory" changes
DEPLOYMENT_ROOTS = (
    "silo-core/deployments/",
    "silo-vaults/deployments/",
    "silo-oracles/deployments/",
)

# CC usernames for the PR comment
CC_USERS = ["yvesfracari", "jean-neiverth"]


def is_factory_deployment_path(relpath: str) -> bool:
    """True if path is under a deployment root and filename is a factory (*Factory*.sol.json)."""
    if not any(relpath.startswith(root) for root in DEPLOYMENT_ROOTS):
        return False
    name = Path(relpath).name
    if not name.endswith(".sol.json"):
        return False
    return "Factory" in name


def contract_name_from_path(relpath: str) -> str:
    """e.g. silo-core/deployments/arbitrum_one/SiloFactory.sol.json -> SiloFactory"""
    return Path(relpath).stem.removesuffix(".sol")


def get_changed_files(base: str, head: str, repo_root: Path) -> list[str]:
    """Return list of changed file paths (relative to repo root) between base and head."""
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...{head}"],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git diff failed: {result.stderr}")
    return [p.strip() for p in result.stdout.strip().splitlines() if p.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List changed factory deployments and optionally format as PR comment.",
    )
    parser.add_argument(
        "--base",
        required=True,
        help="Base git ref (e.g. origin/master or pull request base SHA).",
    )
    parser.add_argument(
        "--head",
        default="HEAD",
        help="Head git ref (default: HEAD).",
    )
    parser.add_argument(
        "--format",
        choices=["names", "comment"],
        default="names",
        help="Output: 'names' = one contract name per line; 'comment' = full markdown comment body.",
    )
    parser.add_argument(
        "--cc",
        nargs="*",
        default=CC_USERS,
        help="GitHub usernames to CC in the comment (default: yvesfracari jean-neiverth).",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    changed = get_changed_files(args.base, args.head, repo_root)
    factory_paths = [p for p in changed if is_factory_deployment_path(p)]
    contract_names = sorted({contract_name_from_path(p) for p in factory_paths})

    if args.format == "names":
        for name in contract_names:
            print(name)
        return 0

    # Format as PR comment body
    if not contract_names:
        body_lines = [
            "🏭 **Factories**",
            "",
            "No factory deployment changes in this PR.",
        ]
    else:
        body_lines = [
            "🏭 **Factories**",
            "",
            "Changed factory deployments (contract names):",
            "",
        ]
        for name in contract_names:
            body_lines.append(f"- `{name}`")
        body_lines.append("")
        body_lines.append("⚠️ Do not copy or use these addresses until this PR is merged. This is a notification only; after merge, use the new deployment addresses.")
        body_lines.append("")
    if args.cc:
        body_lines.append("CC: " + " ".join(f"@{u}" for u in args.cc))

    print("\n".join(body_lines))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
