#!/usr/bin/env python3
"""
Download Standard JSON (Solidity standard-json input) for all contracts deployed on Arbitrum.

This script scans deployment artifacts in:
  - silo-core/deployments/arbitrum_one/*.sol.json

Each deployment json is expected to include:
  - "address": "0x..."

For each address it runs:
  python3 scripts/get_standard_json.py --network arbitrum_one --address <address>

Example:

  python3 scripts/get_arbitrum_deployments_standard_jsons.py

  # custom output directory for downloaded standard json files
  python3 scripts/get_arbitrum_deployments_standard_jsons.py --output-dir flattened/arbitrum_one
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Download standard-json for all Arbitrum deployments."
    )
    p.add_argument(
        "--deployments-dir",
        default="silo-core/deployments/arbitrum_one",
        help="Directory containing *.sol.json deployment artifacts.",
    )
    p.add_argument(
        "--network",
        default="arbitrum_one",
        help="Network passed to scripts/get_standard_json.py.",
    )
    p.add_argument(
        "--output-dir",
        default="flattened/arbitrum_one",
        help="Output directory for downloaded *.standard.json files.",
    )
    p.add_argument(
        "--only",
        default="",
        help="Optional substring filter for deployment filenames (e.g. 'Tower').",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing them.",
    )
    return p.parse_args()


def _read_address(deployment_json_path: Path) -> str:
    data = json.loads(deployment_json_path.read_text(encoding="utf-8"))
    addr = (data.get("address") or "").strip()
    if not (isinstance(addr, str) and addr.startswith("0x") and len(addr) >= 42):
        raise ValueError(f"Missing/invalid 'address' in {deployment_json_path}")
    return addr


def main() -> int:
    args = parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    deployments_dir = (repo_root / args.deployments_dir).resolve()

    if not deployments_dir.exists():
        print(f"Deployments dir not found: {deployments_dir}", file=sys.stderr)
        return 2

    deployment_files = sorted(deployments_dir.glob("*.sol.json"))
    if args.only:
        deployment_files = [p for p in deployment_files if args.only in p.name]

    if not deployment_files:
        print("No deployment files found.", file=sys.stderr)
        return 0

    script = repo_root / "scripts" / "get_standard_json.py"
    if not script.exists():
        print(f"Missing script: {script}", file=sys.stderr)
        return 2

    failures: list[str] = []

    for deployment_file in deployment_files:
        contract_name = deployment_file.name.removesuffix(".sol.json")
        address = _read_address(deployment_file)

        cmd = [
            sys.executable,
            str(script),
            "--network",
            args.network,
            "--address",
            address,
            "--output-dir",
            args.output_dir,
            # keep stable filenames even if explorer ContractName differs
            "--contract",
            contract_name,
        ]

        print(f"[{contract_name}] {address}")
        print(" ".join(cmd))
        if args.dry_run:
            continue

        proc = subprocess.run(cmd, cwd=str(repo_root))
        if proc.returncode != 0:
            failures.append(contract_name)

    if failures:
        print(
            f"Failed for {len(failures)} contracts: {', '.join(failures)}",
            file=sys.stderr,
        )
        return 1

    print(f"Done. Downloaded {len(deployment_files)} standard json files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

