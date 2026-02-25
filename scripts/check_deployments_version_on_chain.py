#!/usr/bin/env python3
"""
CI script: for each deployed contract (core/oracle/vaults deployments) that has
a VERSION in the repo (function VERSION() or constant VERSION), check that the
contract on-chain returns the same version via SiloLens.getVersions(address[]).

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
# OracleFactory.ORACLE_IMPLEMENTATION() getter (public immutable)
ORACLE_IMPLEMENTATION_SELECTOR = "0xa8f39f66"

# SiloVaultDeployer.SILO_VAULTS_FACTORY() getter (public immutable)
SILO_VAULTS_FACTORY_SELECTOR = "0x8dd579c9"

# SiloDeployer immutable getters: (display_name, selector, contract_name for expected version)
SILO_DEPLOYER_GETTERS: list[tuple[str, str, str]] = [
    ("InterestRateModelV2Factory (via SiloDeployer)", "0x28cdfde0", "InterestRateModelV2Factory"),
    ("DynamicKinkModelFactory (via SiloDeployer)", "0x0ec00513", "DynamicKinkModelFactory"),
    ("SiloFactory (via SiloDeployer)", "0x5956617c", "SiloFactory"),
    ("Silo (via SiloDeployer)", "0xdb35c403", "Silo"),
    ("ShareProtectedCollateralToken (via SiloDeployer)", "0xc2bcfc51", "ShareProtectedCollateralToken"),
    ("ShareDebtToken (via SiloDeployer)", "0x654ec411", "ShareDebtToken"),
]

COMPONENT_PATHS: dict[str, dict[str, str]] = {
    "core": {
        "contracts_root": "silo-core/contracts",
        "deployments_root": "silo-core/deployments",
    },
    "oracle": {
        "contracts_root": "silo-oracles/contracts",
        "deployments_root": "silo-oracles/deployments",
    },
    "vaults": {
        "contracts_root": "silo-vaults/contracts",
        "deployments_root": "silo-vaults/deployments",
    },
}

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
_RE_VERSION_ASSIGN = re.compile(
    r'function\s+VERSION\s*\([^)]*\)[^{]*\{[^}]*?=\s*"([^"]+)"\s*;',
    re.MULTILINE | re.DOTALL,
)
_RE_ORACLE_IMPLEMENTATION_TYPE = re.compile(
    r"\b([A-Za-z_][A-Za-z0-9_]*)\s+public\s+immutable\s+ORACLE_IMPLEMENTATION\b"
)
_RE_ORACLE_FACTORY_NEW_IMPL = re.compile(
    r"OracleFactory\s*\(\s*address\s*\(\s*new\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
    re.MULTILINE,
)




def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Check that deployed contracts have on-chain version equal to repo version (via SiloLens)."
    )
    p.add_argument("--chain", required=True, help="Chain name (e.g. arbitrum_one, mainnet).")
    p.add_argument("--rpc-url", default=None, help="RPC URL. If not set, uses env from CHAIN_TO_RPC_ENV.")
    p.add_argument(
        "--components",
        default="core,oracle,vaults",
        help="Comma-separated list: core,oracle,vaults. Default: core,oracle,vaults",
    )
    p.add_argument("--dry-run", action="store_true", help="Only list contracts and expected versions, no RPC.")
    p.add_argument("--verbose", action="store_true", help="Print raw RPC response on getVersions (for debugging read failed).")
    return p.parse_args()


def find_contract_source(repo_root: Path, contract_name: str, contracts_root: Path) -> Path | None:
    """Return path to ContractName.sol under component contracts root, or None."""
    base = repo_root / contracts_root
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
    m = _RE_VERSION_ASSIGN.search(text)
    if m:
        return m.group(1).strip()
    m = _RE_VERSION_CONST.search(text)
    if m:
        return m.group(1).strip()
    return None


def collect_deployments(
    repo_root: Path, chain: str, deployments_root: Path
) -> list[tuple[str, str, list[dict] | None]]:
    """(contract_name, address, abi) for <deployments_root>/<chain>/*.json, sorted by name."""
    base = repo_root / deployments_root / chain
    if not base.exists():
        return []
    out: list[tuple[str, str, list[dict] | None]] = []
    for j in base.glob("*.json"):
        try:
            data = json.loads(j.read_text(encoding="utf-8"))
            addr = (data.get("address") or "").strip()
            if isinstance(addr, str) and addr.startswith("0x") and len(addr) >= 42:
                name = j.stem
                if name.endswith(".sol"):
                    name = name[:-4]
                abi = data.get("abi")
                out.append((name, addr.lower(), abi if isinstance(abi, list) else None))
        except (json.JSONDecodeError, OSError):
            continue
    out.sort(key=lambda x: x[0])
    return out


def get_silo_lens_address(repo_root: Path, chain: str) -> str | None:
    """SiloLens deployment address for chain, or None."""
    base = repo_root / Path(COMPONENT_PATHS["core"]["deployments_root"]) / chain
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


def abi_has_zero_arg_function(abi: list[dict] | None, function_name: str) -> bool:
    if not abi:
        return False
    for item in abi:
        if not isinstance(item, dict):
            continue
        if item.get("type") != "function":
            continue
        if item.get("name") != function_name:
            continue
        inputs = item.get("inputs")
        if isinstance(inputs, list) and len(inputs) == 0:
            return True
    return False


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


def call_zero_arg_address_getter(rpc_url: str, contract_address: str, selector: str) -> str | None:
    result = _eth_call(rpc_url, contract_address, selector)
    if not result or len(result) < 64:
        return None
    h = result[2:] if result.startswith("0x") else result
    return "0x" + h[-40:].lower()


def find_oracle_impl_contract_name(factory_src: Path) -> str | None:
    """Infer oracle implementation contract name from factory source."""
    try:
        text = factory_src.read_text(encoding="utf-8")
    except OSError:
        return None
    m_new = _RE_ORACLE_FACTORY_NEW_IMPL.search(text)
    if m_new:
        return m_new.group(1)
    m = _RE_ORACLE_IMPLEMENTATION_TYPE.search(text)
    if m and m.group(1).lower() != "address":
        return m.group(1)
    return None


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    chain = args.chain.strip()
    components = [c.strip() for c in args.components.split(",") if c.strip()]
    for c in components:
        if c not in COMPONENT_PATHS:
            print(f"Unknown component: {c}. Allowed: {list(COMPONENT_PATHS.keys())}", file=sys.stderr)
            return 2

    rpc_env = CHAIN_TO_RPC_ENV.get(chain)
    rpc_url = args.rpc_url or (os.environ.get(rpc_env) if rpc_env else None)
    if not args.dry_run and not rpc_url:
        hint = rpc_env or f"RPC_<chain>"
        print(f"RPC URL not set. Use --rpc-url or set env {hint}", file=sys.stderr)
        return 2

    all_deployments: list[tuple[str, str, str]] = []
    deployments_by_key: dict[tuple[str, str], str] = {}
    abi_by_key: dict[tuple[str, str], list[dict] | None] = {}
    for component in components:
        dep_root = Path(COMPONENT_PATHS[component]["deployments_root"])
        deployments = collect_deployments(repo_root, chain, dep_root)
        for name, addr, abi in deployments:
            all_deployments.append((component, name, addr))
            deployments_by_key[(component, name)] = addr
            abi_by_key[(component, name)] = abi

    if not all_deployments:
        print(f"No deployments found for chain={chain}, components={components}", file=sys.stderr)
        return 0

    silo_lens = get_silo_lens_address(repo_root, chain)
    if not args.dry_run and not silo_lens:
        print(f"SiloLens not deployed for chain={chain}", file=sys.stderr)
        return 2
    if args.verbose and not args.dry_run:
        rpc_display = (rpc_url[:50] + "..." if rpc_url and len(rpc_url) > 50 else rpc_url) if rpc_url else "(none)"
        print(f"[verbose] chain={chain} SiloLens={silo_lens} rpc={rpc_display}", file=sys.stderr)

    # Build expected version per contract (only for those with VERSION in repo)
    expected_by_key: dict[tuple[str, str], str] = {}
    for component, name, _addr in all_deployments:
        contracts_root = Path(COMPONENT_PATHS[component]["contracts_root"])
        src = find_contract_source(repo_root, name, contracts_root)
        if src:
            v = extract_version_from_sol(src)
            if v is not None:
                expected_by_key[(component, name)] = v

    has_failure = False
    skip_count = 0
    ok_count = 0
    fail_count = 0
    failed_contracts: list[tuple[str, str, str]] = []  # (component, display_name, address)

    dkm_impl_name = "DynamicKinkModel (via DynamicKinkModelFactory)"
    dkm_expected: str | None = None
    if ("core", "DynamicKinkModelFactory") in deployments_by_key:
        dkm_src = find_contract_source(repo_root, "DynamicKinkModel", Path(COMPONENT_PATHS["core"]["contracts_root"]))
        dkm_expected = extract_version_from_sol(dkm_src) if dkm_src else None

    # Oracle factory custom checks:
    # if ABI has ORACLE_IMPLEMENTATION(), call it and verify returned implementation contract version.
    oracle_custom_checks: list[tuple[str, str, str, str]] = []
    # tuple: (display_name, factory_name, impl_name, expected_version)
    for key in sorted(deployments_by_key.keys(), key=lambda x: (x[0], x[1])):
        component, factory_name = key
        if component != "oracle":
            continue
        abi = abi_by_key.get(key)
        if not abi_has_zero_arg_function(abi, "ORACLE_IMPLEMENTATION"):
            continue

        contracts_root = Path(COMPONENT_PATHS["oracle"]["contracts_root"])
        factory_src = find_contract_source(repo_root, factory_name, contracts_root)
        impl_name = None
        if factory_src:
            impl_name = find_oracle_impl_contract_name(factory_src)
        if not impl_name and factory_name.endswith("Factory"):
            impl_name = factory_name[:-7]  # fallback convention: FooFactory -> Foo
        if not impl_name:
            continue
        impl_src = find_contract_source(repo_root, impl_name, contracts_root)
        if not impl_src:
            continue
        impl_expected = extract_version_from_sol(impl_src)
        if impl_expected is None:
            continue
        display_name = f"{impl_name} (via {factory_name}.ORACLE_IMPLEMENTATION)"
        oracle_custom_checks.append((display_name, factory_name, impl_name, impl_expected))

    # SiloDeployer immutable getters: check that each pointed-to contract has current version.
    silo_deployer_checks: list[tuple[str, str, str]] = []  # (display_name, expected_version, selector)
    if ("core", "SiloDeployer") in deployments_by_key:
        core_contracts = Path(COMPONENT_PATHS["core"]["contracts_root"])
        for display_name, selector, contract_name in SILO_DEPLOYER_GETTERS:
            src = find_contract_source(repo_root, contract_name, core_contracts)
            if not src:
                continue
            expected = extract_version_from_sol(src)
            if expected is None:
                continue
            silo_deployer_checks.append((display_name, expected, selector))

    # When vaults SiloVaultsFactory address equals SiloVaultDeployer.SILO_VAULTS_FACTORY(), show "via SiloVaultDeployer" in output.
    display_name_override: dict[tuple[str, str], str] = {}
    if not args.dry_run and ("vaults", "SiloVaultsFactory") in deployments_by_key and ("vaults", "SiloVaultDeployer") in deployments_by_key:
        vault_deployer_addr = deployments_by_key[("vaults", "SiloVaultDeployer")]
        factory_from_deployer = call_zero_arg_address_getter(rpc_url, vault_deployer_addr, SILO_VAULTS_FACTORY_SELECTOR)
        factory_deployed_addr = deployments_by_key[("vaults", "SiloVaultsFactory")]
        if factory_from_deployer and factory_from_deployer.lower() == factory_deployed_addr.lower():
            display_name_override[("vaults", "SiloVaultsFactory")] = "SiloVaultsFactory (via SiloVaultDeployer)"

    # One RPC call: getVersions(address[]) for all versioned contracts + IRM + oracle impls + SiloDeployer immutables.
    # Build explicit (name, address) pairs in sorted order so name and result stay paired.
    versioned_keys = sorted(expected_by_key.keys(), key=lambda x: (x[0], x[1]))
    key_addr_pairs = [(k, deployments_by_key[k]) for k in versioned_keys]
    on_chain_by_key: dict[tuple[str, str], str | None] = {}
    irm_addr: str | None = None
    oracle_impl_addr_by_display: dict[str, str | None] = {}
    silo_deployer_addr_by_display: dict[str, str | None] = {}
    if not args.dry_run:
        addresses = [addr for _, addr in key_addr_pairs]
        if dkm_expected:
            irm_addr = call_factory_irm(rpc_url, deployments_by_key[("core", "DynamicKinkModelFactory")])
            if irm_addr:
                addresses.append(irm_addr)
        for display_name, factory_name, _impl_name, _expected in oracle_custom_checks:
            factory_addr = deployments_by_key.get(("oracle", factory_name))
            if not factory_addr:
                continue
            impl_addr = call_zero_arg_address_getter(rpc_url, factory_addr, ORACLE_IMPLEMENTATION_SELECTOR)
            oracle_impl_addr_by_display[display_name] = impl_addr
            if impl_addr:
                addresses.append(impl_addr)
        deployer_addr = deployments_by_key.get(("core", "SiloDeployer"))
        if deployer_addr:
            for display_name, _expected, selector in silo_deployer_checks:
                addr = call_zero_arg_address_getter(rpc_url, deployer_addr, selector)
                silo_deployer_addr_by_display[display_name] = addr
                if addr:
                    addresses.append(addr)
        if addresses:
            on_chain_list = get_versions_on_chain(rpc_url, silo_lens, addresses, verbose=args.verbose)
            n_versioned = len(key_addr_pairs)
            versions_for_versioned = on_chain_list[:n_versioned]
            for (key, _), version in zip(key_addr_pairs, versions_for_versioned):
                on_chain_by_key[key] = version
            extra_idx = n_versioned
            if dkm_expected and irm_addr and len(on_chain_list) > extra_idx:
                on_chain_by_key[("core", dkm_impl_name)] = on_chain_list[extra_idx]
                extra_idx += 1
            for display_name, _factory_name, _impl_name, _expected in oracle_custom_checks:
                impl_addr = oracle_impl_addr_by_display.get(display_name)
                if not impl_addr:
                    continue
                if len(on_chain_list) > extra_idx:
                    on_chain_by_key[("oracle", display_name)] = on_chain_list[extra_idx]
                extra_idx += 1
            for display_name, _expected, _selector in silo_deployer_checks:
                if silo_deployer_addr_by_display.get(display_name):
                    if len(on_chain_list) > extra_idx:
                        on_chain_by_key[("core", display_name)] = on_chain_list[extra_idx]
                    extra_idx += 1

    all_deployments.sort(key=lambda x: (x[0], x[1]))
    for component, name, addr in all_deployments:
        expected = expected_by_key.get((component, name))

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

        on_chain = on_chain_by_key.get((component, name))
        name_display = display_name_override.get((component, name), name)
        if on_chain is None:
            print(f"[FAIL] {component} {name_display} expected {expected} on_chain (read failed) {addr}")
            has_failure = True
            fail_count += 1
            failed_contracts.append((component, name_display, addr))
            continue
        if on_chain == expected:
            print(f"[ ok ] {component} {name_display} {expected}")
            ok_count += 1
            continue
        print(f"[FAIL] {component} {name_display} expected {expected} on_chain {on_chain} {addr}")
        has_failure = True
        fail_count += 1
        failed_contracts.append((component, name_display, addr))

    # Custom check: DynamicKinkModel version via DynamicKinkModelFactory.IRM() (version fetched in same batch above)
    if ("core", "DynamicKinkModelFactory") in deployments_by_key and dkm_expected is not None:
        if args.dry_run:
            print(f"[dry-run] core {dkm_impl_name} {dkm_expected}")
        else:
            dkm_on_chain = on_chain_by_key.get(("core", dkm_impl_name))
            if dkm_on_chain is None:
                irm_addr_for_fail = irm_addr if irm_addr else "(IRM address unknown)"
                print(f"[FAIL] core expected {dkm_expected} on_chain (read failed) {irm_addr_for_fail}")
                has_failure = True
                fail_count += 1
                if irm_addr:
                    failed_contracts.append(("core", dkm_impl_name, irm_addr))
            elif dkm_on_chain == dkm_expected:
                print(f"[ ok ] core {dkm_impl_name} {dkm_expected}")
                ok_count += 1
            else:
                irm_addr_fail = irm_addr if irm_addr else "(IRM address unknown)"
                print(f"[FAIL] core expected {dkm_expected} on_chain {dkm_on_chain} {irm_addr_fail}")
                has_failure = True
                fail_count += 1
                if irm_addr:
                    failed_contracts.append(("core", dkm_impl_name, irm_addr))

    # Custom checks: oracle implementations from factory ORACLE_IMPLEMENTATION()
    for display_name, factory_name, _impl_name, expected in oracle_custom_checks:
        if args.dry_run:
            print(f"[dry-run] oracle {display_name} {expected}")
            continue

        impl_addr = oracle_impl_addr_by_display.get(display_name)
        if not impl_addr:
            factory_addr = deployments_by_key.get(("oracle", factory_name), "(factory address unknown)")
            print(
                f"[FAIL] oracle expected {expected} on_chain (read failed) "
                f"{factory_addr} (failed ORACLE_IMPLEMENTATION call)"
            )
            has_failure = True
            fail_count += 1
            continue

        on_chain = on_chain_by_key.get(("oracle", display_name))
        if on_chain is None:
            print(f"[FAIL] oracle expected {expected} on_chain (read failed) {impl_addr}")
            has_failure = True
            fail_count += 1
            failed_contracts.append(("oracle", display_name, impl_addr))
            continue
        if on_chain == expected:
            print(f"[ ok ] oracle {display_name} {expected}")
            ok_count += 1
            continue
        print(f"[FAIL] oracle expected {expected} on_chain {on_chain} {impl_addr}")
        has_failure = True
        fail_count += 1
        failed_contracts.append(("oracle", display_name, impl_addr))

    # Custom checks: SiloDeployer immutable getters (SILO_IMPL, SILO_FACTORY, etc.)
    for display_name, expected, _selector in silo_deployer_checks:
        if args.dry_run:
            print(f"[dry-run] core {display_name} {expected}")
            continue
        impl_addr = silo_deployer_addr_by_display.get(display_name)
        if not impl_addr:
            deployer_addr = deployments_by_key.get(("core", "SiloDeployer"), "(SiloDeployer address unknown)")
            print(
                f"[FAIL] core expected {expected} on_chain (read failed) "
                f"{deployer_addr} (failed getter for {display_name})"
            )
            has_failure = True
            fail_count += 1
            continue
        on_chain = on_chain_by_key.get(("core", display_name))
        if on_chain is None:
            print(f"[FAIL] core {display_name} expected {expected} on_chain (read failed) {impl_addr}")
            has_failure = True
            fail_count += 1
            failed_contracts.append(("core", display_name, impl_addr))
            continue
        if on_chain == expected:
            print(f"[ ok ] core {display_name} {expected}")
            ok_count += 1
            continue
        print(f"[FAIL] core {display_name} expected {expected} on_chain {on_chain} {impl_addr}")
        has_failure = True
        fail_count += 1
        failed_contracts.append(("core", display_name, impl_addr))

    if args.dry_run:
        print(f"Dry-run: {len(expected_by_key)} versioned, {len(all_deployments) - len(expected_by_key)} skipped.")
        return 0

    print()
    print(f"Summary: skipped={skip_count} ok={ok_count} fail={fail_count}")
    print()

    if failed_contracts:
        print()
        print("Contracts with outdated versions (name, address):")
        for component, display_name, address in failed_contracts:
            print(f"  - {component}/{display_name}, {address}")
        print()

    return 1 if has_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
