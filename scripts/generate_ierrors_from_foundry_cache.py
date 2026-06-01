#!/usr/bin/env python3
"""
Generate common/utils/interfaces/IErrors.sol from Foundry artifacts.

The script scans cache/foundry/out recursively, extracts all ABI entries
with type == "error", deduplicates by canonical Solidity signature, sorts
alphabetically, and writes the interface file.

usage:
    python3 scripts/generate_ierrors_from_foundry_cache.py
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ARTIFACTS_ROOT = ROOT / "cache" / "foundry" / "out"
IERRORS_PATH = ROOT / "common" / "utils" / "interfaces" / "IErrors.sol"


def canonical_param_type(param: dict[str, Any]) -> str:
    param_type = param.get("type")
    if not isinstance(param_type, str) or not param_type:
        raise ValueError(f"Invalid parameter type in ABI: {param}")

    # ABI encodes tuples as "tuple", "tuple[]", "tuple[2]" etc.
    tuple_suffix = ""
    if param_type.startswith("tuple"):
        tuple_suffix = param_type[len("tuple") :]
        components = param.get("components")
        if not isinstance(components, list):
            raise ValueError(f"Tuple without components in ABI: {param}")
        inner = ",".join(canonical_param_type(c) for c in components)
        return f"({inner}){tuple_suffix}"

    return param_type


def error_signature(entry: dict[str, Any]) -> str:
    name = entry.get("name")
    if not isinstance(name, str) or not name:
        raise ValueError(f"Invalid error name in ABI: {entry}")

    inputs = entry.get("inputs", [])
    if not isinstance(inputs, list):
        raise ValueError(f"Invalid error inputs in ABI: {entry}")

    arg_types = ",".join(canonical_param_type(i) for i in inputs)
    return f"{name}({arg_types})"


def collect_error_signatures() -> set[str]:
    if not ARTIFACTS_ROOT.is_dir():
        raise SystemExit(
            f"Missing artifacts dir: {ARTIFACTS_ROOT}\n"
            "Run one or more forge build/test commands first."
        )

    signatures: set[str] = set()
    for json_path in ARTIFACTS_ROOT.rglob("*.json"):
        try:
            data = json.loads(json_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        abi = data.get("abi")
        if not isinstance(abi, list):
            continue

        for entry in abi:
            if not isinstance(entry, dict):
                continue
            if entry.get("type") != "error":
                continue
            try:
                signatures.add(error_signature(entry))
            except ValueError:
                # Skip malformed ABI fragments; we only care about valid entries.
                continue

    return signatures


def signature_to_declaration(signature: str) -> str:
    return f"    error {signature};"


def build_ierrors_content(signatures: list[str]) -> str:
    lines = [
        "// SPDX-License-Identifier: GPL-2.0-or-later",
        "pragma solidity >=0.8.4;",
        "",
        "interface IErrors {",
    ]

    for sig in signatures:
        lines.append(signature_to_declaration(sig))

    lines.extend(["}", ""])
    return "\n".join(lines)


def main() -> None:
    signatures = sorted(collect_error_signatures())
    content = build_ierrors_content(signatures)
    IERRORS_PATH.write_text(content, encoding="utf-8")
    print(f"Wrote {IERRORS_PATH} with {len(signatures)} errors.")


if __name__ == "__main__":
    main()
