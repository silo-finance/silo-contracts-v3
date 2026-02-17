#!/usr/bin/env python3
"""
Generate ReadMe.md with core contract names and SPDX licenses.

Scans only:
- silo-oracles/contracts
- silo-core/contracts
- silo-vaults/contracts

Skips interfaces and libraries.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]

# Prefer explicit "*-contracts" names if they exist, otherwise use repo paths.
TARGET_DIRS = [
    ("silo-oracles-contracts", "silo-oracles/contracts"),
    ("silo-core-contracts", "silo-core/contracts"),
    ("silo-volts-contracts", "silo-vaults/contracts"),
]

OUTPUT_FILE = ROOT / "LICENSES.md"

LICENSE_RE = re.compile(r"SPDX-License-Identifier:\s*([^\s*]+)")
CONTRACT_RE = re.compile(r"\b(?:abstract\s+)?contract\s+([A-Za-z_][A-Za-z0-9_]*)\b")
INTERFACE_RE = re.compile(r"\binterface\s+([A-Za-z_][A-Za-z0-9_]*)\b")
LIBRARY_RE = re.compile(r"\blibrary\s+([A-Za-z_][A-Za-z0-9_]*)\b")
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_RE = re.compile(r"//.*?$", re.MULTILINE)


def resolve_target_dirs() -> list[Path]:
    resolved: list[Path] = []
    for preferred, fallback in TARGET_DIRS:
        preferred_path = ROOT / preferred
        fallback_path = ROOT / fallback
        if preferred_path.exists():
            resolved.append(preferred_path)
        elif fallback_path.exists():
            resolved.append(fallback_path)
    return resolved


def is_interface_or_library_path(path: Path) -> bool:
    lowered_parts = [part.lower() for part in path.parts]
    return any(part in {"interface", "interfaces", "library", "libraries"} for part in lowered_parts)


def list_solidity_files(target_dirs: Iterable[Path]) -> list[Path]:
    files: list[Path] = []
    for directory in target_dirs:
        files.extend(
            file
            for file in directory.rglob("*.sol")
            if file.is_file() and not is_interface_or_library_path(file.relative_to(ROOT))
        )
    return sorted(set(files))


def strip_comments(content: str) -> str:
    no_block = BLOCK_COMMENT_RE.sub("", content)
    return LINE_COMMENT_RE.sub("", no_block)


def extract_license(content: str) -> str:
    match = LICENSE_RE.search(content)
    return match.group(1) if match else "UNKNOWN"


def extract_contract_names(content: str) -> list[str]:
    clean = strip_comments(content)

    # Defensive check: we only export "contract" declarations.
    contract_names = CONTRACT_RE.findall(clean)
    _ = INTERFACE_RE.findall(clean)
    _ = LIBRARY_RE.findall(clean)

    return contract_names


def generate() -> int:
    target_dirs = resolve_target_dirs()
    if not target_dirs:
        raise SystemExit(
            "No target directories found. Expected one of:\n"
            "- silo-oracles-contracts or silo-oracles/contracts\n"
            "- silo-core-contracts or silo-core/contracts\n"
            "- silo-volts-contracts or silo-vaults/contracts"
        )

    records: list[tuple[str, str]] = []
    for solidity_file in list_solidity_files(target_dirs):
        content = solidity_file.read_text(encoding="utf-8")
        license_name = extract_license(content)
        for contract_name in extract_contract_names(content):
            records.append((contract_name, license_name))

    records.sort(key=lambda x: x[0].lower())

    lines = [
        "# Main Contracts and Licenses",
        "",
        "Generated from:",
        *[f"- `{path.relative_to(ROOT)}`" for path in target_dirs],
        "",
        "| Contract | License |",
        "|---|---|",
    ]

    if records:
        lines.extend(f"| {name} | {license_name} |" for name, license_name in records)
    else:
        lines.append("| (none found) | - |")

    OUTPUT_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Saved {OUTPUT_FILE.relative_to(ROOT)} with {len(records)} contract entries.")
    return 0


if __name__ == "__main__":
    raise SystemExit(generate())
