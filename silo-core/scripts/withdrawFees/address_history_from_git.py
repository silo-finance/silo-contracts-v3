#!/usr/bin/env python3
"""
List address history for a JSON deployment artifact across git commits.

Example:
  python3 silo-core/scripts/withdrawFees/address_history_from_git.py \
    --file silo-core/deployments/base/SiloFactory.sol.json \
    --branch develop
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass
class CommitEntry:
    commit: str
    file_path: str


@dataclass
class AddressEntry:
    commit: str
    short_commit: str
    date: str
    file_path: str
    address: str


def run_git(args: list[str], repo_root: Path) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or "(no stderr)"
        raise RuntimeError(f"git {' '.join(args)} failed: {stderr}")
    return result.stdout


def normalize_repo_relative_path(repo_root: Path, user_path: str) -> str:
    path_obj = Path(user_path)
    if path_obj.is_absolute():
        path_obj = path_obj.resolve()
        try:
            return str(path_obj.relative_to(repo_root))
        except ValueError as exc:
            raise ValueError(f"Path {user_path} is outside repository root {repo_root}") from exc

    return str(path_obj)


def parse_commits_with_paths(log_output: str, initial_path: str) -> list[CommitEntry]:
    entries: list[CommitEntry] = []
    current_path = initial_path
    current_commit: str | None = None
    status_lines: list[str] = []

    def flush_commit() -> None:
        nonlocal current_path, current_commit, status_lines
        if current_commit is None:
            return

        entries.append(CommitEntry(commit=current_commit, file_path=current_path))

        # Track path backwards through history:
        # if commit renamed old -> new and new is current_path at this commit,
        # then older commits should be read from old path.
        for raw in status_lines:
            line = raw.strip()
            if not line:
                continue

            parts = line.split("\t")
            status = parts[0]

            if status.startswith("R") and len(parts) >= 3:
                old_path = parts[1]
                new_path = parts[2]
                if new_path == current_path:
                    current_path = old_path
            elif status.startswith("C") and len(parts) >= 3:
                old_path = parts[1]
                new_path = parts[2]
                if new_path == current_path:
                    current_path = old_path

        current_commit = None
        status_lines = []

    for line in log_output.splitlines():
        if line.startswith("__COMMIT__"):
            flush_commit()
            current_commit = line.removeprefix("__COMMIT__").strip()
            continue

        if current_commit is None:
            continue

        if line.strip():
            status_lines.append(line)

    flush_commit()
    return entries


def get_address_from_file_content(file_content: str, json_key: str) -> str | None:
    try:
        payload = json.loads(file_content)
    except json.JSONDecodeError:
        return None

    value = payload.get(json_key)
    if isinstance(value, str) and value:
        return value
    return None


def iter_address_entries(
    repo_root: Path,
    commit_entries: Iterable[CommitEntry],
    json_key: str,
) -> list[AddressEntry]:
    result: list[AddressEntry] = []
    for entry in commit_entries:
        try:
            content = run_git(["show", f"{entry.commit}:{entry.file_path}"], repo_root)
        except RuntimeError:
            # Can happen for edge history cases; skip safely.
            continue

        address = get_address_from_file_content(content, json_key)
        if not address:
            continue

        date = run_git(["show", "-s", "--format=%ci", entry.commit], repo_root).strip()
        result.append(
            AddressEntry(
                commit=entry.commit,
                short_commit=entry.commit[:8],
                date=date,
                file_path=entry.file_path,
                address=address,
            )
        )

    return result


def filter_only_changes(entries: list[AddressEntry]) -> list[AddressEntry]:
    if not entries:
        return entries

    filtered = [entries[0]]
    for item in entries[1:]:
        if item.address.lower() != filtered[-1].address.lower():
            filtered.append(item)
    return filtered


def format_output(entries: list[AddressEntry], only_addresses: bool) -> str:
    if only_addresses:
        return "\n".join(entry.address for entry in entries)

    lines = ["address | commit | date | file_path"]
    lines.append("-" * 100)
    for entry in entries:
        lines.append(f"{entry.address} | {entry.short_commit} | {entry.date} | {entry.file_path}")
    return "\n".join(lines)


def infer_rpc_env_var_from_path(target_path: str) -> str:
    parts = Path(target_path).parts
    chain_name: str | None = None

    if "deployments" in parts:
        idx = parts.index("deployments")
        if idx + 1 < len(parts):
            chain_name = parts[idx + 1]

    if not chain_name:
        raise ValueError(
            "Cannot infer chain from path. Expected segment like deployments/<chain>/..."
        )

    aliases = {
        "arbitrum_one": "ARBITRUM",
        "arbitrum": "ARBITRUM",
        "ethereum": "MAINNET",
        "eth_mainnet": "MAINNET",
    }
    normalized_chain = aliases.get(chain_name.lower(), chain_name)
    sanitized = re.sub(r"[^a-zA-Z0-9]+", "_", normalized_chain).strip("_").upper()
    return f"RPC_{sanitized}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List historical address values from a JSON file in git history."
    )
    parser.add_argument(
        "--file",
        required=True,
        help="Path to tracked file (repo-relative or absolute).",
    )
    parser.add_argument(
        "--branch",
        default="HEAD",
        help="Branch/ref to inspect, e.g. develop, master, HEAD (default).",
    )
    parser.add_argument(
        "--json-key",
        default="address",
        help="Top-level JSON key that contains the address (default: address).",
    )
    parser.add_argument(
        "--include-duplicates",
        action="store_true",
        help="Include commits where address did not change.",
    )
    parser.add_argument(
        "--follow-renames",
        action="store_true",
        help="Follow git renames/copies when traversing file history.",
    )
    parser.add_argument(
        "--only-addresses",
        action="store_true",
        help="Output TASKS-ready lines in format \"<address> <RPC_ENV_VAR>\".",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        repo_root = Path(run_git(["rev-parse", "--show-toplevel"], Path.cwd()).strip())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    try:
        target_path = normalize_repo_relative_path(repo_root, args.file)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    log_cmd = [
        "log",
        args.branch,
        "--name-status",
        "--format=__COMMIT__%H",
        "--",
        target_path,
    ]
    if args.follow_renames:
        log_cmd.insert(2, "--follow")

    try:
        log_output = run_git(log_cmd, repo_root)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    commit_entries = parse_commits_with_paths(log_output, target_path)
    if not commit_entries:
        print("No commits found for this file on the given branch.", file=sys.stderr)
        return 1

    address_entries = iter_address_entries(
        repo_root=repo_root,
        commit_entries=commit_entries,
        json_key=args.json_key,
    )
    if not address_entries:
        print(
            f"No valid '{args.json_key}' values found in file history on branch {args.branch}.",
            file=sys.stderr,
        )
        return 1

    if not args.include_duplicates:
        address_entries = filter_only_changes(address_entries)

    if args.only_addresses:
        try:
            rpc_env_var = infer_rpc_env_var_from_path(target_path)
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        print("\n".join(f"  \"{entry.address} {rpc_env_var}\"" for entry in address_entries))
    else:
        print(format_output(address_entries, only_addresses=args.only_addresses))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
