#!/usr/bin/env python3
"""
CI script: for each deployed contract (silo-core deployments) that has a VERSION
in the repo (function VERSION() or constant VERSION), check that the contract
on-chain returns the same version via SiloLens.getVersions(address[]).

- [ ok ]: component contract_name version
- [skip]: component contract_name (no VERSION in repo)
- [FAIL]: component expected version_expected on_chain version_on_chain

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
# DynamicKinkModelFactory.IRM() getter (public immutable)
IRM_SELECTOR = "0x1e75db16"
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
    p.add_argument("--verbose", action="store_true", help="Print raw RPC response on getVersions (for debugging read failed).")
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
    result, _ = _eth_call_with_error(rpc_url, to, data)
    return result


def _eth_call_with_error(rpc_url: str, to: str, data: str) -> tuple[str | None, str | None]:
    """Like _eth_call but returns (result, error_message). error_message is set when RPC returns error."""
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
    except (HTTPError, URLError, OSError, json.JSONDecodeError, KeyError) as e:
        return None, str(e)
    err = body.get("error")
    if err:
        msg = err.get("message", err) if isinstance(err, dict) else str(err)
        return None, msg
    return (body.get("result") or "").strip() or None, None


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
        # For dynamic arrays of dynamic types, element offsets are relative to
        # the start of element-head section (right after array length).
        elem_offset = int(hex_result[elem_offset_hex : elem_offset_hex + 64], 16)
        elem_absolute_offset = array_offset + 32 + elem_offset
        s = _abi_decode_string_at(hex_result, elem_absolute_offset)
        out.append(s)
    return out


def _encode_address_array(addresses: list[str]) -> str:
    """ABI-encode address[] for getVersions(address[]) calldata (after selector)."""
    n = len(addresses)
    # offset to array = 32 (one word) = 64 hex chars
    offset_hex = "0" * 62 + "20"
    length_hex = hex(n)[2:].zfill(64)
    parts = [offset_hex, length_hex]
    for a in addresses:
        a = a.lower().replace("0x", "").zfill(64)
        parts.append(a)
    return "".join(parts)


def _debug_decode_layout(hex_result: str) -> None:
    """Print ABI layout hint for first words (offset, length, first elem offset) to stderr."""
    h = hex_result.strip().removeprefix("0x")
    if len(h) < 128:
        print("[verbose] decode layout: result too short for ABI", file=sys.stderr)
        return
    try:
        array_offset = int(h[0:64], 16)
        base = array_offset * 2
        length = int(h[base : base + 64], 16) if base + 64 <= len(h) else -1
        print(f"[verbose] decode layout: array_offset={array_offset} (0x{array_offset:x}) length={length}", file=sys.stderr)
        if length > 0 and base + 64 + 64 <= len(h):
            first_elem_offset = int(h[base + 64 : base + 128], 16)
            print(f"[verbose] decode layout: first elem offset={first_elem_offset} (0x{first_elem_offset:x})", file=sys.stderr)
    except ValueError as e:
        print(f"[verbose] decode layout parse error: {e}", file=sys.stderr)


def get_versions_on_chain(
    rpc_url: str, lens_address: str, addresses: list[str], *, verbose: bool = False
) -> list[str | None]:
    """Call SiloLens.getVersions(addresses), return list of decoded strings (same order as addresses)."""
    if not addresses:
        return []
    data = GET_VERSIONS_SELECTOR + _encode_address_array(addresses)
    if verbose:
        print(f"[verbose] getVersions: lens={lens_address} addresses={len(addresses)}", file=sys.stderr)
        print(f"[verbose] first 2 addrs: {addresses[:2]}", file=sys.stderr)
        result, err = _eth_call_with_error(rpc_url, lens_address, data)
        if err:
            print(f"[verbose] RPC error: {err}", file=sys.stderr)
        print(f"[verbose] result: len={len(result) if result else 0}", file=sys.stderr)
        if result:
            cap = 1500
            print(f"[verbose] raw hex (first {min(cap, len(result))} chars): {result[:cap]}", file=sys.stderr)
    else:
        result = _eth_call(rpc_url, lens_address, data)
    if result is None:
        if not verbose:
            print("getVersions failed (RPC error or revert). Run with --verbose for details.", file=sys.stderr)
        return [None] * len(addresses)
    decoded = _abi_decode_string_array(result)
    if verbose:
        print(f"[verbose] decode: len(decoded)={len(decoded)} expected={len(addresses)}", file=sys.stderr)
        if decoded:
            for i, v in enumerate(decoded[:3]):
                print(f"[verbose] decoded[{i}] = {repr(v)}", file=sys.stderr)
        if len(decoded) != len(addresses) or all(v is None for v in decoded):
            _debug_decode_layout(result)
    if len(decoded) != len(addresses):
        if not verbose:
            print("getVersions returned data but decode length mismatch. Run with --verbose.", file=sys.stderr)
        return [None] * len(addresses)
    # getVersion always returns a string (e.g. "legacy" on catch); treat decode failure as "legacy"
    return [v if v is not None and v != "" else "legacy" for v in decoded]


def call_factory_irm(rpc_url: str, factory_address: str) -> str | None:
    """Call DynamicKinkModelFactory.IRM(), return implementation address (DynamicKinkModel) or None."""
    result = _eth_call(rpc_url, factory_address, IRM_SELECTOR)
    if not result or len(result) < 64:
        return None
    h = result[2:] if result.startswith("0x") else result
    return "0x" + h[-40:].lower()


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
    if args.verbose and not args.dry_run:
        rpc_display = (rpc_url[:50] + "..." if rpc_url and len(rpc_url) > 50 else rpc_url) if rpc_url else "(none)"
        print(f"[verbose] chain={chain} SiloLens={silo_lens} rpc={rpc_display}", file=sys.stderr)

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
    skip_count = 0
    ok_count = 0
    fail_count = 0
    component = "core"  # this script checks silo-core deployments only

    dkm_impl_name = "DynamicKinkModel (via DynamicKinkModelFactory.IRM)"
    dkm_expected: str | None = None
    if "DynamicKinkModelFactory" in deployments_by_name:
        dkm_src = find_contract_source(repo_root, "DynamicKinkModel")
        dkm_expected = extract_version_from_sol(dkm_src) if dkm_src else None

    # One RPC call: getVersions(address[]) for all versioned contracts + IRM address if applicable.
    # Build explicit (name, address) pairs in sorted order so name and result stay paired.
    versioned_names = sorted(expected_by_name.keys())
    name_addr_pairs = [(n, deployments_by_name[n]) for n in versioned_names]
    on_chain_by_name: dict[str, str | None] = {}
    if not args.dry_run:
        addresses = [addr for _, addr in name_addr_pairs]
        irm_addr: str | None = None
        if dkm_expected:
            irm_addr = call_factory_irm(rpc_url, deployments_by_name["DynamicKinkModelFactory"])
            if irm_addr:
                addresses.append(irm_addr)
        if addresses:
            on_chain_list = get_versions_on_chain(rpc_url, silo_lens, addresses, verbose=args.verbose)
            n_versioned = len(name_addr_pairs)
            versions_for_versioned = on_chain_list[:n_versioned]
            for (name, _), version in zip(name_addr_pairs, versions_for_versioned):
                on_chain_by_name[name] = version
            if dkm_expected and len(addresses) > n_versioned and len(on_chain_list) == len(addresses):
                on_chain_by_name[dkm_impl_name] = on_chain_list[-1]

    for name in sorted(deployments_by_name.keys()):
        expected = expected_by_name.get(name)
        addr = deployments_by_name[name]

        if expected is None:
            if args.dry_run:
                print(f"[dry-run] skip {component} {name} (no VERSION)")
            else:
                print(f"[skip] {component} {name}")
                skip_count += 1
            continue

        if args.dry_run:
            print(f"[dry-run] {component} {name} {expected}")
            continue

        on_chain = on_chain_by_name.get(name)
        if on_chain is None:
            print(f"[FAIL] {component} expected {expected} on_chain (read failed) {addr}")
            has_failure = True
            fail_count += 1
            continue
        if on_chain == expected:
            print(f"[ ok ] {component} {name} {expected}")
            ok_count += 1
            continue
        print(f"[FAIL] {component} expected {expected} on_chain {on_chain} {addr}")
        has_failure = True
        fail_count += 1

    # Custom check: DynamicKinkModel version via DynamicKinkModelFactory.IRM() (version fetched in same batch above)
    if "DynamicKinkModelFactory" in deployments_by_name and dkm_expected is not None:
        if args.dry_run:
            print(f"[dry-run] {component} {dkm_impl_name} {dkm_expected}")
        else:
            dkm_on_chain = on_chain_by_name.get(dkm_impl_name)
            if dkm_on_chain is None:
                irm_addr_for_fail = irm_addr if irm_addr else "(IRM address unknown)"
                print(f"[FAIL] {component} expected {dkm_expected} on_chain (read failed) {irm_addr_for_fail}")
                has_failure = True
                fail_count += 1
            elif dkm_on_chain == dkm_expected:
                print(f"[ ok ] {component} {dkm_impl_name} {dkm_expected}")
                ok_count += 1
            else:
                irm_addr_fail = irm_addr if irm_addr else "(IRM address unknown)"
                print(f"[FAIL] {component} expected {dkm_expected} on_chain {dkm_on_chain} {irm_addr_fail}")
                has_failure = True
                fail_count += 1

    if args.dry_run:
        print(f"Dry-run: {len(expected_by_name)} versioned, {len(deployments_by_name) - len(expected_by_name)} skipped.")
        return 0

    print(f"Summary: skipped={skip_count} ok={ok_count} fail={fail_count}")
    return 1 if has_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
