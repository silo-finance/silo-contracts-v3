#!/usr/bin/env python3
"""Stage 1: collect every SiloFactory address from git history into data/<chain>.json.

Walks the git history (master + develop) of the EXACT path
`silo-core/deployments/<chain>/SiloFactory.sol.json`, newest -> oldest, reading the
`address` field at each commit. New unique factory addresses are merged into the
per-chain data file. Incremental: stops as soon as it reaches an address already
saved in the data file (delete the file to force a full re-scan).

NOTE: we deliberately do NOT use `git log --follow`. Rename/copy detection compares
file *content*, and every chain's `SiloFactory.sol.json` is near-identical JSON, so
`--follow` would jump into other chains' history and collect foreign factory
addresses that never belonged to this chain.

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


def build_timeline(ref: str, path: str, json_key: str) -> list[TimelineEntry]:
    """Newest -> oldest list of (address, commit, date) for the tracked file.

    Follows ONLY the exact path (no --follow / rename / copy detection). This is
    deliberate: every chain has its own `SiloFactory.sol.json`, and those files are
    near-identical JSON, so git's rename/copy heuristic would otherwise jump into a
    different chain's history and collect factory addresses that never belonged to
    this chain.
    """
    log_output = run_git([
        "log",
        ref,
        "--format=__COMMIT__%H %ci",
        "--",
        path,
    ])

    timeline: list[TimelineEntry] = []
    for line in log_output.splitlines():
        if not line.startswith("__COMMIT__"):
            continue
        rest = line[len("__COMMIT__"):].strip()
        commit, _, date = rest.partition(" ")
        if not commit:
            continue
        address = address_at_commit(commit, path, json_key)
        if address:
            timeline.append(
                TimelineEntry(
                    address=address,
                    commit=commit,
                    short_commit=commit[:8],
                    date=date,
                )
            )

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

    # Sanity check: any factory on file that never appears in git history for this
    # chain's exact path is stale/foreign (e.g. left over from the old --follow bug).
    git_addresses = {e.address.lower() for e in full_timeline}
    if git_addresses:
        stale = [addr for addr in data["factories"] if addr.lower() not in git_addresses]
        if stale:
            print("", file=sys.stderr)
            print(
                f"WARNING: {len(stale)} factory address(es) on file are NOT in the git "
                f"history of {deployment_path}:",
                file=sys.stderr,
            )
            for addr in stale:
                print(f"  ! {addr}", file=sys.stderr)
            print(
                "  These do not belong to this chain and should be removed from the data file.",
                file=sys.stderr,
            )

    if full_timeline:
        origin = min(full_timeline, key=lambda e: e.date)
        print("")
        print(f"Origin of {deployment_path} (oldest commit in history):")
        print(f"  commit : {origin.short_commit}")
        print(f"  date   : {origin.date}")

        print("")
        print("Full address timeline (newest -> oldest, deduped per branch order):")
        print("  address | commit | date")
        printed: set[tuple[str, str]] = set()
        for e in full_timeline:
            key = (e.address.lower(), e.commit)
            if key in printed:
                continue
            printed.add(key)
            print(f"  {e.address} | {e.short_commit} | {e.date}")

    print(f"\nTotal factories on file for {chain.alias}: {len(data['factories'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
