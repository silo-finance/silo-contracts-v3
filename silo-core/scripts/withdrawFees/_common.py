#!/usr/bin/env python3
"""Shared helpers for the withdrawFees pipeline (chain metadata, .env, cast/Multicall3)."""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

# Canonical Multicall3 address (same on every supported chain).
MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11"


@dataclass(frozen=True)
class Chain:
    alias: str  # matches silo-core/deployments/<alias>/ and ChainsLib alias
    chain_id: int
    rpc_env: str  # name of the RPC url env var in .env


# Single source of truth for chains. Aliases match `silo-core/deployments/<alias>/`
# and `ChainsLib`. RPC env var names match the historical .env convention.
CHAINS: dict[str, Chain] = {
    c.alias: c
    for c in (
        Chain("arbitrum_one", 42161, "RPC_ARBITRUM"),
        Chain("avalanche", 43114, "RPC_AVALANCHE"),
        Chain("base", 8453, "RPC_BASE"),
        Chain("bnb", 56, "RPC_BNB"),
        Chain("injective", 1776, "RPC_INJECTIVE"),
        Chain("ink", 57073, "RPC_INK"),
        Chain("mainnet", 1, "RPC_MAINNET"),
        Chain("mantle", 5000, "RPC_MANTLE"),
        Chain("megaeth", 4326, "RPC_MEGAETH"),
        Chain("okx", 196, "RPC_OKX"),
        Chain("optimism", 10, "RPC_OPTIMISM"),
        Chain("sonic", 146, "RPC_SONIC"),
        Chain("xdc", 50, "RPC_XDC"),
    )
}


def get_chain(alias: str) -> Chain:
    chain = CHAINS.get(alias)
    if chain is None:
        known = ", ".join(sorted(CHAINS))
        raise ValueError(f"Unknown chain alias '{alias}'. Known aliases: {known}")
    return chain


@lru_cache(maxsize=1)
def repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
        if out:
            return Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    # Fallback: .../silo-core/scripts/withdrawFees/_common.py -> repo root
    return Path(__file__).resolve().parents[3]


def data_dir() -> Path:
    return Path(__file__).resolve().parent / "data"


def data_file(alias: str) -> Path:
    return data_dir() / f"{alias}.json"


def load_dotenv(dotenv_path: Path | None = None) -> dict[str, str]:
    """Minimal .env parser (KEY=VALUE, supports `export` and quotes)."""
    if dotenv_path is None:
        dotenv_path = repo_root() / ".env"

    values: dict[str, str] = {}
    if not dotenv_path.exists():
        return values

    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        values[key] = value
    return values


# ----------------------------------------------------------------------------
# cast / Multicall3 helpers
# ----------------------------------------------------------------------------

ZERO_ADDRESS = "0x" + "0" * 40


def _run_cast(args: list[str]) -> str:
    result = subprocess.run(["cast", *args], text=True, capture_output=True)
    if result.returncode != 0:
        stderr = result.stderr.strip() or "(no stderr)"
        raise RuntimeError(f"cast {' '.join(args)} failed: {stderr}")
    return result.stdout.strip()


@lru_cache(maxsize=64)
def selector(signature: str) -> str:
    """4-byte function selector, e.g. selector("getSilos()") -> '0xaecc90cb'."""
    return _run_cast(["sig", signature])


def encode_uint_call(signature: str, value: int) -> str:
    """Calldata for a single-uint function, e.g. idToSiloConfig(uint256)."""
    return selector(signature) + f"{value:064x}"


def encode_address_call(signature: str, address: str) -> str:
    """Calldata for a single-address function, e.g. protocolFees(address)."""
    raw = address[2:] if address.startswith("0x") else address
    return selector(signature) + raw.lower().rjust(64, "0")


def deployment_address(alias: str, contract_file: str) -> str:
    """Read the `address` field of silo-core/deployments/<alias>/<contract_file>."""
    path = repo_root() / "silo-core" / "deployments" / alias / contract_file
    return json.loads(path.read_text(encoding="utf-8"))["address"]


def cast_call_uint(rpc_url: str, to: str, signature_with_return: str) -> int:
    """Call a no-arg view returning a single uint."""
    out = _run_cast(["call", to, signature_with_return, "--rpc-url", rpc_url, "--json"])
    return int(json.loads(out)[0], 0)


# cast renders a (bool,bytes)[] result as "[(true, 0x..), (false, 0x), ...]"
_PAIR_RE = re.compile(r"\((true|false),\s*(0x[0-9a-fA-F]*)\)")


def _parse_pairs(cast_output: str) -> list[tuple[bool, str]]:
    return [(flag == "true", data) for flag, data in _PAIR_RE.findall(cast_output)]


def aggregate3(
    rpc_url: str,
    calls: list[tuple[str, str]],
    batch_size: int = 400,
) -> list[tuple[bool, str]]:
    """Multicall3.aggregate3 read with allowFailure=true.

    `calls` is a list of (target, calldataHex). Returns a list of
    (success, returnDataHex) in the same order. Batched to keep calldata sane.
    """
    results: list[tuple[bool, str]] = []
    sig = "aggregate3((address,bool,bytes)[])((bool,bytes)[])"

    for start in range(0, len(calls), batch_size):
        batch = calls[start:start + batch_size]
        tuples = ",".join(f"({target},true,{data})" for target, data in batch)
        out = _run_cast(["call", MULTICALL3, sig, f"[{tuples}]", "--rpc-url", rpc_url])
        pairs = _parse_pairs(out)
        if len(pairs) != len(batch):
            raise RuntimeError(
                f"aggregate3 returned {len(pairs)} results for {len(batch)} calls; output: {out[:200]}"
            )
        results.extend(pairs)

    return results


def decode_address(return_data: str) -> str:
    """Decode a 32-byte ABI word into a checksummed-ish lowercase address."""
    raw = return_data[2:] if return_data.startswith("0x") else return_data
    if len(raw) < 64:
        return ZERO_ADDRESS
    return "0x" + raw[-40:]


def is_zero_address(addr: str) -> bool:
    return addr.lower() == ZERO_ADDRESS
