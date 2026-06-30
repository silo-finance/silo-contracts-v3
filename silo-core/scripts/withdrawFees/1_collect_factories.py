#!/usr/bin/env python3
"""Stage 1: collect every SiloFactory address from git history into data/<chain>.json.

Walks the git history (master + develop) of
`silo-core/deployments/<chain>/SiloFactory.sol.json`, newest -> oldest, reading the
`address` field at each commit. New unique factory addresses are merged into the
per-chain data file. Incremental: stops as soon as it reaches an address already
saved in the data file (delete the file to force a full re-scan).

Usage:
  python3 silo-core/scripts/withdrawFees/1_collect_factories.py --chain arbitrum_one
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import _common


@dataclass
class TimelineEntry:
    address: str
    commit: str
    short_commit: str
    date: str
    path: str
    origin_status: str  # status of this path at this commit: A / M / R<old> / ...


def run_git(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=_common.repo_root(),
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or "(no stderr)"
        raise RuntimeError(f"git {' '.join(args)} failed: {stderr}")
    return result.stdout


def resolve_ref(ref: str) -> str | None:
    """Return a usable ref (local or origin/<ref>), or None if it does not exist."""
    for candidate in (ref, f"origin/{ref}"):
        check = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"{candidate}^{{commit}}"],
            cwd=_common.repo_root(),
            text=True,
            capture_output=True,
        )
        if check.returncode == 0:
            return candidate
    return None


def address_at_commit(commit: str, path: str, json_key: str) -> str | None:
    try:
        content = run_git(["show", f"{commit}:{path}"])
    except RuntimeError:
        return None
    try:
        payload = json.loads(content)
    except json.JSONDecodeError:
        return None
    value = payload.get(json_key)
    return value if isinstance(value, str) and value else None


def build_timeline(ref: str, initial_path: str, json_key: str) -> list[TimelineEntry]:
    """Newest -> oldest list of (address, commit, date, path) for the tracked file.

    Uses --follow so renames/moves are traversed back to the file's true origin.
    """
    log_output = run_git([
        "log",
        ref,
        "--follow",
        "--name-status",
        "--format=__COMMIT__%H %ci",
        "--",
        initial_path,
    ])

    timeline: list[TimelineEntry] = []
    current_path = initial_path
    commit: str | None = None
    date: str = ""
    status_lines: list[str] = []

    def flush() -> None:
        nonlocal commit, date, current_path, status_lines
        if commit is None:
            return

        origin_status = "?"
        next_path = current_path
        for raw in status_lines:
            parts = raw.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            status = parts[0]
            if status.startswith(("R", "C")) and len(parts) >= 3:
                old_path, new_path = parts[1], parts[2]
                if new_path == current_path:
                    origin_status = f"{status} from {old_path}"
                    next_path = old_path
            elif parts[-1] == current_path:
                origin_status = status

        address = address_at_commit(commit, current_path, json_key)
        if address:
            timeline.append(
                TimelineEntry(
                    address=address,
                    commit=commit,
                    short_commit=commit[:8],
                    date=date,
                    path=current_path,
                    origin_status=origin_status,
                )
            )

        current_path = next_path
        commit = None
        date = ""
        status_lines = []

    for line in log_output.splitlines():
        if line.startswith("__COMMIT__"):
            flush()
            rest = line[len("__COMMIT__"):].strip()
            commit, _, date = rest.partition(" ")
            continue
        if commit is None:
            continue
        if line.strip():
            status_lines.append(line)
    flush()

    return timeline


def load_data_file(path: Path, alias: str, chain_id: int) -> dict:
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
    else:
        data = {}
    data.setdefault("chain", alias)
    data.setdefault("chainId", chain_id)
    data.setdefault("factories", {})
    # consumable list of {silo, asset, symbol, decimals}, filled/maintained in stage 2
    data.setdefault("silos", [])
    # drop superseded shapes from older runs
    for legacy_key in ("siloIds", "siloSymbols", "siloDecimals", "siloMeta"):
        data.pop(legacy_key, None)
    return data


def save_data_file(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain", required=True, help="Chain alias, e.g. arbitrum_one")
    parser.add_argument(
        "--branches",
        nargs="+",
        default=["master", "develop"],
        help="Branches to scan (default: master develop).",
    )
    parser.add_argument("--json-key", default="address", help="JSON key holding the address.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        chain = _common.get_chain(args.chain)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    deployment_path = f"silo-core/deployments/{chain.alias}/SiloFactory.sol.json"
    if not (_common.repo_root() / deployment_path).exists():
        print(f"ERROR: {deployment_path} not found in repo.", file=sys.stderr)
        return 1

    out_path = _common.data_file(chain.alias)
    data = load_data_file(out_path, chain.alias, chain.chain_id)
    known = {addr.lower() for addr in data["factories"]}

    print(f"[{chain.alias}] collecting factory addresses from git history -> {out_path}")

    full_timeline: list[TimelineEntry] = []
    new_addresses: list[str] = []
    seen_new: set[str] = set()

    for branch in args.branches:
        ref = resolve_ref(branch)
        if ref is None:
            print(f"  - branch '{branch}' not found (local or origin), skipping")
            continue

        timeline = build_timeline(ref, deployment_path, args.json_key)
        if not timeline:
            print(f"  - {ref}: no history for {deployment_path}")
            continue

        full_timeline.extend(timeline)
        print(f"  - {ref}: {len(timeline)} commits with an address")

        # newest -> oldest, stop at first already-known address (incremental)
        for entry in timeline:
            low = entry.address.lower()
            if low in known:
                print(f"    reached already-saved address {entry.address} ({entry.short_commit}); stopping branch scan")
                break
            if low in seen_new:
                continue
            seen_new.add(low)
            new_addresses.append(entry.address)

    # Add new factories (preserve any existing per-factory discovery data).
    for addr in new_addresses:
        data["factories"].setdefault(addr, {"startId": None, "lastCheckedId": None, "silos": []})

    save_data_file(out_path, data)

    # --- report ---
    print("")
    print(f"Added {len(new_addresses)} new factory address(es):")
    for addr in new_addresses:
        print(f"  + {addr}")
    if not new_addresses:
        print("  (none - data file already up to date)")

    if full_timeline:
        origin = min(full_timeline, key=lambda e: e.date)
        print("")
        print("Origin of SiloFactory.sol.json (oldest commit in history):")
        print(f"  commit : {origin.short_commit}")
        print(f"  date   : {origin.date}")
        print(f"  path   : {origin.path}")
        print(f"  status : {origin.origin_status}")
        if origin.origin_status.startswith(("R", "C")):
            print("  NOTE: origin is a rename/copy - verify the original path above is the true start.")
        elif not origin.origin_status.startswith("A"):
            print("  NOTE: oldest commit is not an 'A' (add); history may extend beyond what --follow traced.")

        print("")
        print("Full address timeline (newest -> oldest, deduped per branch order):")
        print("  address | commit | date | path | status")
        printed: set[tuple[str, str]] = set()
        for e in full_timeline:
            key = (e.address.lower(), e.commit)
            if key in printed:
                continue
            printed.add(key)
            print(f"  {e.address} | {e.short_commit} | {e.date} | {e.path} | {e.origin_status}")

    print(f"\nTotal factories on file for {chain.alias}: {len(data['factories'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
