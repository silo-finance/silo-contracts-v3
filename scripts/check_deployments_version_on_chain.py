#!/usr/bin/env python3
"""
CI script: for each deployed contract (silo-core deployments) that has a VERSION
in the repo (function VERSION() or constant VERSION), check that the contract
on-chain returns the same version via SiloLens.getVersion(address).

- [ ok ]: component contract_name version
- [skip]: component contract_name (no VERSION in repo)
- [FAIL]: component contract_name version_expected version_on_chain

Output is sorted alphabetically by contract name. Uses same chain/RPC/env as
check_deployments_owner_is_dao.py.

python3 scripts/check_deployments_version_on_chain.py --chain arbitrum_one
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# getVersions(address[]) selector
GET_VERSIONS_SELECTOR = "0xf58e82b5"
# getVersion(address) selector (fallback when getVersions fails or decode fails)
GET_VERSION_SELECTOR = "0xc3f82bc3"
CONTRACTS_ROOT = Path("silo-core/contracts")
DEPLOYMENTS_ROOT = Path("silo-core/deployments")

CHAIN_TO_RPC_ENV: dict[str, str] = {
    "arbitrum_one": "RPC_ARBITRUM",
    "avalanche": "RPC_AVALANCHE",
    "base": "RPC_BASE",
    "bnb": "RPC_BNB",
    "injective": "RPC_INJECTIVE",
    "ink": "RPC_INK",
    "mainnet": "RPC_MAINNET",
    "okx": "RPC_OKX",
    "optimism": "RPC_OPTIMISM",
    "sonic": "RPC_SONIC",
}

# Regex: constant VERSION = "Name X.Y.Z"; or (in VERSION function) return "Name X.Y.Z";
_RE_VERSION_CONST = re.compile(r'VERSION\s*=\s*"([^"]+)"\s*;', re.MULTILINE)
# After "function VERSION(...)" find return "..." within the same function (next ~400 chars)
_RE_VERSION_RETURN = re.compile(
    r'function\s+VERSION\s*\([^)]*\)[^{]*\{[^}]*?return\s+"([^"]+)"\s*;',
    re.MULTILINE | re.DOTALL,
)




def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Check that deployed contracts have on-chain version equal to repo version (via SiloLens)."
    )
    p.add_argument("--chain", required=True, help="Chain name (e.g. arbitrum_one, mainnet).")
    p.add_argument("--rpc-url", default=None, help="RPC URL. If not set, uses env from CHAIN_TO_RPC_ENV.")
    p.add_argument("--dry-run", action="store_true", help="Only list contracts and expected versions, no RPC.")
    return p.parse_args()


def find_contract_source(repo_root: Path, contract_name: str) -> Path | None:
    """Return path to ContractName.sol under silo-core/contracts, or None."""
    base = repo_root / CONTRACTS_ROOT
    candidates = list(base.rglob(f"{contract_name}.sol"))
    for c in candidates:
        if c.stem == contract_name:
            return c
    return None


def extract_version_from_sol(sol_path: Path) -> str | None:
    """Extract VERSION string from .sol file (function VERSION() return \"...\" or constant VERSION = \"...\")."""
    try:
        text = sol_path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = _RE_VERSION_RETURN.search(text)
    if m:
        return m.group(1).strip()
    m = _RE_VERSION_CONST.search(text)
    if m:
        return m.group(1).strip()
    return None


def collect_deployments(repo_root: Path, chain: str) -> list[tuple[str, str]]:
    """(contract_name, address) for silo-core/deployments/<chain>/*.json, sorted by name."""
    base = repo_root / DEPLOYMENTS_ROOT / chain
    if not base.exists():
        return []
    out: list[tuple[str, str]] = []
    for j in base.glob("*.json"):
        try:
            data = json.loads(j.read_text(encoding="utf-8"))
            addr = (data.get("address") or "").strip()
            if isinstance(addr, str) and addr.startswith("0x") and len(addr) >= 42:
                name = j.stem
                if name.endswith(".sol"):
                    name = name[:-4]
                out.append((name, addr.lower()))
        except (json.JSONDecodeError, OSError):
            continue
    out.sort(key=lambda x: x[0])
    return out


def get_silo_lens_address(repo_root: Path, chain: str) -> str | None:
    """SiloLens deployment address for chain, or None."""
    base = repo_root / DEPLOYMENTS_ROOT / chain
    j = base / "SiloLens.sol.json"
    if not j.exists():
        return None
    try:
        data = json.loads(j.read_text(encoding="utf-8"))
        addr = (data.get("address") or "").strip()
        if isinstance(addr, str) and addr.startswith("0x") and len(addr) >= 42:
            return addr.lower()
    except (json.JSONDecodeError, OSError):
        pass
    return None


def _eth_call(rpc_url: str, to: str, data: str) -> str | None:
    to = to if to.startswith("0x") else "0x" + to
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [{"to": to, "data": data}, "latest"],
    }
    try:
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError, URLError

        req = Request(
            rpc_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError, OSError, json.JSONDecodeError, KeyError):
        return None
    if body.get("error"):
        return None
    return (body.get("result") or "").strip() or None


def _abi_decode_string_at(hex_data: str, byte_offset: int) -> str | None:
    """Decode one ABI string at byte_offset in hex_data (full return hex). At offset: 32 bytes length, then utf8."""
    start = byte_offset * 2
    if start + 64 > len(hex_data):
        return None
    try:
        length = int(hex_data[start : start + 64], 16)
        if length == 0:
            return ""
        data_start = start + 64
        if data_start + length * 2 > len(hex_data):
            return None
        data_hex = hex_data[data_start : data_start + length * 2]
        return bytes.fromhex(data_hex).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None


def _abi_decode_string_array(hex_result: str) -> list[str | None]:
    """Decode ABI-encoded string[] (offset to array, then length, then per-element offsets, then strings)."""
    if not hex_result or not hex_result.strip():
        return []
    hex_result = hex_result.strip()
    if hex_result.startswith("0x"):
        hex_result = hex_result[2:]
    if len(hex_result) < 128:
        return []
    try:
        array_offset = int(hex_result[0:64], 16)  # bytes from start
        base = array_offset * 2
        length = int(hex_result[base : base + 64], 16)
    except ValueError:
        return []
    out: list[str | None] = []
    for i in range(length):
        elem_offset_hex = base + 64 + i * 64
        if elem_offset_hex + 64 > len(hex_result):
            out.append(None)
            continue
        elem_offset = int(hex_result[elem_offset_hex : elem_offset_hex + 64], 16)
        s = _abi_decode_string_at(hex_result, elem_offset)
        out.append(s)
    return out


def _encode_address_array(addresses: list[str]) -> str:
    """ABI-encode address[] for getVersions(address[]) calldata (after selector)."""
    n = len(addresses)
    # offset to array = 32 (one word)
    offset_hex = "0" * 63 + "20"
    length_hex = hex(n)[2:].zfill(64)
    parts = [offset_hex, length_hex]
    for a in addresses:
        a = a.lower().replace("0x", "").zfill(64)
        parts.append(a)
    return "".join(parts)


def _abi_decode_single_string(hex_result: str) -> str | None:
    """Decode ABI-encoded single string: word0 = offset to data, at offset: length (32b) then utf8."""
    if not hex_result or len(hex_result) < 2 + 128:
        return None
    h = hex_result[2:] if hex_result.startswith("0x") else hex_result
    try:
        offset_bytes = int(h[0:64], 16)
        offset_hex = offset_bytes * 2
        if len(h) < offset_hex + 64:
            return None
        length = int(h[offset_hex : offset_hex + 64], 16)
        if length == 0:
            return ""
        start = offset_hex + 64
        if len(h) < start + length * 2:
            return None
        return bytes.fromhex(h[start : start + length * 2]).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None


def get_version_on_chain(rpc_url: str, lens_address: str, contract_address: str) -> str | None:
    """Call SiloLens.getVersion(contract_address), return decoded string or None (fallback)."""
    addr_hex = contract_address.lower().replace("0x", "").zfill(64)
    data = GET_VERSION_SELECTOR + addr_hex
    result = _eth_call(rpc_url, lens_address, data)
    return _abi_decode_single_string(result) if result else None


def get_versions_on_chain(rpc_url: str, lens_address: str, addresses: list[str]) -> list[str | None]:
    """Call SiloLens.getVersions(addresses), return list of decoded strings (same order as addresses)."""
    if not addresses:
        return []
    data = GET_VERSIONS_SELECTOR + _encode_address_array(addresses)
    result = _eth_call(rpc_url, lens_address, data)
    if result is None:
        return [None] * len(addresses)
    decoded = _abi_decode_string_array(result)
    if len(decoded) != len(addresses) or all(v is None for v in decoded):
        return [None] * len(addresses)
    return decoded


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    chain = args.chain.strip()

    rpc_env = CHAIN_TO_RPC_ENV.get(chain)
    rpc_url = args.rpc_url or (os.environ.get(rpc_env) if rpc_env else None)
    if not args.dry_run and not rpc_url:
        hint = rpc_env or f"RPC_<chain>"
        print(f"RPC URL not set. Use --rpc-url or set env {hint}", file=sys.stderr)
        return 2

    deployments = collect_deployments(repo_root, chain)
    if not deployments:
        print(f"No deployments found for chain={chain}", file=sys.stderr)
        return 0

    silo_lens = get_silo_lens_address(repo_root, chain)
    if not args.dry_run and not silo_lens:
        print(f"SiloLens not deployed for chain={chain}", file=sys.stderr)
        return 2

    # Build expected version per contract (only for those with VERSION in repo)
    deployments_by_name = {name: addr for name, addr in deployments}
    expected_by_name: dict[str, str] = {}
    for name in deployments_by_name:
        src = find_contract_source(repo_root, name)
        if src:
            v = extract_version_from_sol(src)
            if v is not None:
                expected_by_name[name] = v

    has_failure = False
    component = "core"  # this script checks silo-core deployments only

    # One RPC call: getVersions(address[]) for all versioned contracts; fallback to getVersion per contract if needed
    versioned_names = sorted(expected_by_name.keys())
    on_chain_by_name: dict[str, str | None] = {}
    if not args.dry_run and versioned_names:
        addresses = [deployments_by_name[n] for n in versioned_names]
        on_chain_list = get_versions_on_chain(rpc_url, silo_lens, addresses)
        if len(on_chain_list) == len(addresses) and not all(v is None for v in on_chain_list):
            on_chain_by_name = dict(zip(versioned_names, on_chain_list))
        else:
            for name, addr in zip(versioned_names, addresses):
                on_chain_by_name[name] = get_version_on_chain(rpc_url, silo_lens, addr)

    for name in sorted(deployments_by_name.keys()):
        expected = expected_by_name.get(name)
        addr = deployments_by_name[name]

        if expected is None:
            if args.dry_run:
                print(f"[dry-run] skip {component} {name} (no VERSION)")
            else:
                print(f"[skip] {component} {name}")
            continue

        if args.dry_run:
            print(f"[dry-run] {component} {name} {expected}")
            continue

        on_chain = on_chain_by_name.get(name)
        if on_chain is None:
            print(f"[FAIL] {component} {name} expected {expected} on_chain (read failed)")
            has_failure = True
            continue
        if on_chain == expected:
            print(f"[ ok ] {component} {name} {expected}")
            continue
        print(f"[FAIL] {component} {name} expected {expected} on_chain {on_chain}")
        has_failure = True

    if args.dry_run:
        print(f"Dry-run: {len(expected_by_name)} versioned, {len(deployments_by_name) - len(expected_by_name)} skipped.")
        return 0

    return 1 if has_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
