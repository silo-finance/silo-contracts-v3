#!/usr/bin/env python3
"""Resolve NEW (disk) and OLD (previous distinct address from git file history) liquidation helpers."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = Path(__file__).resolve().parent
DEPLOYMENTS_ROOT = REPO_ROOT / "silo-core" / "deployments"
DEFAULT_OUT_DIR = SCRIPT_DIR / "out"

HELPER_NAME_RE = re.compile(r"(?i)(liquidationhelper|manualliquidationhelper)")


@dataclass(frozen=True)
class HelperPair:
    chain: str
    file_name: str
    file_path: Path
    new_address: str
    old_address: str | None


def is_address(value: str) -> bool:
    value = value.strip()
    if not value.startswith("0x") or len(value) != 42:
        return False
    try:
        int(value[2:], 16)
    except ValueError:
        return False
    return True


def normalize_address(value: str) -> str:
    value = value.strip()
    if not is_address(value):
        raise ValueError(f"Invalid address: {value}")
    return value.lower()


def short(addr: str) -> str:
    a = addr.lower()
    return f"{a[:6]}{a[-4:]}"


def _read_address_from_json_text(text: str) -> str | None:
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    addr = data.get("address")
    if isinstance(addr, str) and is_address(addr):
        return normalize_address(addr)
    return None


def _read_address_from_disk(path: Path) -> str | None:
    try:
        return _read_address_from_json_text(path.read_text(encoding="utf-8"))
    except OSError:
        return None


def _git_log_commits(path: Path) -> list[str]:
    rel = path.relative_to(REPO_ROOT).as_posix()
    try:
        out = subprocess.check_output(
            ["git", "log", "--format=%H", "--", rel],
            cwd=REPO_ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def _git_show_address(commit: str, path: Path) -> str | None:
    rel = path.relative_to(REPO_ROOT).as_posix()
    try:
        out = subprocess.check_output(
            ["git", "show", f"{commit}:{rel}"],
            cwd=REPO_ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return _read_address_from_json_text(out)


def previous_address_from_git(path: Path, new_address: str, *, old_ref: str | None = None) -> str | None:
    """
    Return the previous distinct helper address for this deployment file.

    If old_ref is set, read that ref only (edge-case override).
    Otherwise walk `git log -- <file>` newest-first and return the first address != NEW.
    """
    new_norm = normalize_address(new_address)

    if old_ref:
        addr = _git_show_address(old_ref, path)
        if addr is None or addr == new_norm:
            return None
        return addr

    for commit in _git_log_commits(path):
        addr = _git_show_address(commit, path)
        if addr is None:
            continue
        if addr != new_norm:
            return addr
    return None


def iter_helper_deployment_files(chain: str) -> list[Path]:
    deployments_dir = DEPLOYMENTS_ROOT / chain
    if not deployments_dir.is_dir():
        return []

    files: list[Path] = []
    for path in sorted(deployments_dir.glob("*.json")):
        if HELPER_NAME_RE.search(path.stem):
            files.append(path)
    return files


def resolve_helpers_for_chain(chain: str, *, old_ref: str | None = None) -> list[HelperPair]:
    pairs: list[HelperPair] = []
    for path in iter_helper_deployment_files(chain):
        new_addr = _read_address_from_disk(path)
        if new_addr is None:
            continue
        old_addr = previous_address_from_git(path, new_addr, old_ref=old_ref)
        pairs.append(
            HelperPair(
                chain=chain,
                file_name=path.name,
                file_path=path,
                new_address=new_addr,
                old_address=old_addr,
            )
        )
    return pairs


def collect_new_addresses(pairs: list[HelperPair]) -> list[str]:
    return sorted({p.new_address for p in pairs}, key=str.lower)


def collect_old_addresses(pairs: list[HelperPair]) -> list[str]:
    return sorted({p.old_address for p in pairs if p.old_address}, key=str.lower)


def pairs_to_json(pairs: list[HelperPair]) -> list[dict[str, Any]]:
    return [
        {
            "file": p.file_name,
            "new": p.new_address,
            "old": p.old_address,
        }
        for p in pairs
    ]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Resolve NEW (disk) / OLD (git file history) liquidation helper addresses."
    )
    parser.add_argument(
        "chain_positional",
        nargs="?",
        default="",
        help="Chain alias (positional alternative to --chain).",
    )
    parser.add_argument("--chain", default="", help="Chain alias (e.g. mainnet, bnb).")
    parser.add_argument(
        "--old-ref",
        default="",
        help="Optional git ref override for OLD addresses.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUT_DIR})",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    chain = (args.chain or args.chain_positional or "").strip().lower()
    if not chain:
        print("[FAIL] missing chain (use --chain <alias> or positional <alias>)")
        return 1

    deployments_dir = DEPLOYMENTS_ROOT / chain
    old_ref = args.old_ref.strip() or None

    print(f"[info] chain={chain}")
    print(f"[info] deployments dir: {deployments_dir}")
    if not deployments_dir.is_dir():
        print(f"[FAIL] deployments directory does not exist: {deployments_dir}")
        return 1

    files = iter_helper_deployment_files(chain)
    print(f"[info] helper deployment files found: {len(files)}")
    if not files:
        print("[warn] no LiquidationHelper* / ManualLiquidationHelper* JSON files")
        return 1

    if old_ref:
        print(f"[info] OLD resolution mode: --old-ref={old_ref}")
    else:
        print("[info] OLD resolution mode: git log -- <file> (first address != NEW)")

    print("[info] resolving NEW from disk and OLD from git history...")
    pairs = resolve_helpers_for_chain(chain, old_ref=old_ref)

    skipped = 0
    for path in files:
        if _read_address_from_disk(path) is None:
            skipped += 1
            print(f"[warn] skip (no valid address): {path.name}")

    with_old = 0
    without_old = 0
    for pair in pairs:
        if pair.old_address:
            with_old += 1
            print(f"[ok] {pair.file_name}")
            print(f"       NEW: {pair.new_address}")
            print(f"       OLD: {pair.old_address}  (revoke candidate)")
        else:
            without_old += 1
            print(f"[ok] {pair.file_name}")
            print(f"       NEW: {pair.new_address}")
            print("       OLD: -  (no previous distinct address; grant-only)")

    new_helpers = collect_new_addresses(pairs)
    old_helpers = collect_old_addresses(pairs)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.output_dir / f"helpers_{chain}.json"
    payload: dict[str, Any] = {
        "chain": chain,
        "helpers": pairs_to_json(pairs),
    }
    if old_ref:
        payload["oldRef"] = old_ref
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print()
    print(
        f"[summary] resolved={len(pairs)} with_old={with_old} without_old={without_old} "
        f"skipped={skipped}"
    )
    print(f"[summary] unique NEW={len(new_helpers)} unique OLD={len(old_helpers)}")
    print(f"[done] result written to: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
