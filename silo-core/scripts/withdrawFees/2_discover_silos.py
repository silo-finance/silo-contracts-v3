#!/usr/bin/env python3
"""Stage 2: discover every silo created by the factories in data/<chain>.json.

For each factory (collected by stage 1) it reads `getNextSiloId()`, determines the
starting silo id (cached, or probed among the known bases {1,100,101,3000,3001}),
then batch-reads `idToSiloConfig(id)` + `getSilos()` via Multicall3 and stores
{siloId, siloConfig, silo0, silo1} plus `lastCheckedId` for incremental reruns.

It also enriches each silo with its immutable asset metadata (asset/symbol/decimals)
in a `siloMeta` map, fetched once via Multicall3, so WithdrawFees.s.sol does not have
to read it from chain on every run.

Usage:
  python3 silo-core/scripts/withdrawFees/2_discover_silos.py \
      --chain arbitrum_one --rpc-url $RPC_ARBITRUM
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import _common

ID_TO_CONFIG_SIG = "idToSiloConfig(uint256)"  # current factories: id -> SiloConfig
ID_TO_SILOS_SIG = "idToSilos(uint256)"        # legacy factories: id -> [silo0, silo1]
GET_SILOS_SIG = "getSilos()"
ASSET_SIG = "asset()"
SYMBOL_SIG = "symbol()"
DECIMALS_SIG = "decimals()"

# probe id -> resolved start id (mirrors WithdrawFees.s.sol _resolveStartingSiloId)
START_CANDIDATES: list[tuple[int, int]] = [
    (1, 1),
    (100, 100),
    (101, 100),
    (3000, 3000),
    (3001, 3001),
]


def decode_two_addresses(return_data: str) -> tuple[str, str]:
    raw = return_data[2:] if return_data.startswith("0x") else return_data
    if len(raw) < 128:
        return _common.ZERO_ADDRESS, _common.ZERO_ADDRESS
    return "0x" + raw[24:64], "0x" + raw[88:128]


def decode_uint(return_data: str) -> int:
    hex_str = return_data[2:] if return_data.startswith("0x") else return_data
    return int(hex_str, 16) if hex_str else 0


def decode_string(return_data: str) -> str:
    """Decode an ERC20 symbol() return: ABI string OR a right-padded bytes32."""
    hex_str = return_data[2:] if return_data.startswith("0x") else return_data
    try:
        raw = bytes.fromhex(hex_str)
    except ValueError:
        return ""
    if not raw:
        return ""
    # bytes32-style symbol (e.g. MKR): single word, NUL-padded ascii
    if len(raw) == 32:
        return raw.rstrip(b"\x00").decode("utf-8", "replace").strip()
    # ABI-encoded dynamic string: [offset][length][data...]
    if len(raw) >= 64:
        offset = int.from_bytes(raw[:32], "big")
        if offset + 32 <= len(raw):
            length = int.from_bytes(raw[offset:offset + 32], "big")
            data = raw[offset + 32:offset + 32 + length]
            return data.decode("utf-8", "replace").strip()
    return raw.rstrip(b"\x00").decode("utf-8", "replace").strip()


def configs_for_ids(rpc_url: str, factory: str, ids: list[int]) -> dict[int, str]:
    """Return {siloId: siloConfig} for ids whose idToSiloConfig is a non-zero address."""
    if not ids:
        return {}
    calls = [(factory, _common.encode_uint_call(ID_TO_CONFIG_SIG, i)) for i in ids]
    results = _common.aggregate3(rpc_url, calls)
    out: dict[int, str] = {}
    for silo_id, (success, data) in zip(ids, results):
        if not success:
            continue
        config = _common.decode_address(data)
        if not _common.is_zero_address(config):
            out[silo_id] = config
    return out


def _get_next_silo_id(rpc_url: str, factory: str, attempts: int = 3) -> int:
    """Read getNextSiloId(); every factory has it, so retry transient RPC errors then raise."""
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            return _common.cast_call_uint(rpc_url, factory, "getNextSiloId()(uint256)")
        except RuntimeError as exc:
            last_error = exc
    raise RuntimeError(f"getNextSiloId() failed for {factory} after {attempts} attempts: {last_error}")


def silos_for_configs(rpc_url: str, configs: dict[int, str]) -> dict[int, tuple[str, str]]:
    """Return {siloId: (silo0, silo1)} by calling getSilos() on each config (current factories)."""
    if not configs:
        return {}
    ids = list(configs)
    get_silos_data = _common.selector(GET_SILOS_SIG)
    calls = [(configs[i], get_silos_data) for i in ids]
    results = _common.aggregate3(rpc_url, calls)
    out: dict[int, tuple[str, str]] = {}
    for silo_id, (success, data) in zip(ids, results):
        if not success:
            continue
        silo0, silo1 = decode_two_addresses(data)
        out[silo_id] = (silo0, silo1)
    return out


def legacy_silos_for_ids(rpc_url: str, factory: str, ids: list[int]) -> dict[int, tuple[str, str]]:
    """Return {siloId: (silo0, silo1)} via the legacy idToSilos(uint256) returns (address[2])."""
    if not ids:
        return {}
    calls = [(factory, _common.encode_uint_call(ID_TO_SILOS_SIG, i)) for i in ids]
    results = _common.aggregate3(rpc_url, calls)
    out: dict[int, tuple[str, str]] = {}
    for silo_id, (success, data) in zip(ids, results):
        if not success:
            continue
        silo0, silo1 = decode_two_addresses(data)
        if not _common.is_zero_address(silo0):
            out[silo_id] = (silo0, silo1)
    return out


def resolve_start(rpc_url: str, factory: str, next_id: int) -> tuple[int | None, bool]:
    """Probe the known bases with both ABIs.

    Returns (start_id, legacy). `legacy` is True when the factory exposes the old
    idToSilos(uint256) layout instead of idToSiloConfig(uint256). (None, False) means
    no silo was found at any known base (empty factory).
    """
    probes = [(probe, start) for probe, start in START_CANDIDATES if probe < next_id]
    if not probes:
        return None, False

    probe_ids = [probe for probe, _ in probes]

    # current layout first
    found_new = configs_for_ids(rpc_url, factory, probe_ids)
    for probe, start in probes:
        if probe in found_new:
            return start, False

    # legacy layout fallback (mirrors the old WithdrawFees.s.sol OldFactory.idToSilos path)
    found_legacy = legacy_silos_for_ids(rpc_url, factory, probe_ids)
    for probe, start in probes:
        if probe in found_legacy:
            return start, True

    return None, False


def discover_factory(rpc_url: str, factory: str, record: dict) -> dict:
    """Update `record` in place with discovered silos and return it.

    getNextSiloId() must succeed for every factory; a failure is raised (not skipped)
    so we never silently drop a factory and miss its silos.
    """
    next_id = _get_next_silo_id(rpc_url, factory)
    print(f"  {factory}: nextSiloId={next_id}")

    if next_id <= 1:
        record["lastCheckedId"] = next_id - 1
        print("    no silos minted yet")
        return record

    last_checked = record.get("lastCheckedId")
    start_id = record.get("startId")
    legacy = bool(record.get("legacy", False))

    if last_checked is not None and start_id is not None:
        scan_from = last_checked + 1
    else:
        start_id, legacy = resolve_start(rpc_url, factory, next_id)
        if start_id is None:
            record["lastCheckedId"] = next_id - 1
            print("    no start id among {1,100,101,3000,3001} - empty factory")
            return record
        record["startId"] = start_id
        record["legacy"] = legacy
        scan_from = start_id

    if legacy:
        print("    legacy factory (idToSilos layout)")

    if scan_from >= next_id:
        print("    up to date, nothing new")
        record["lastCheckedId"] = next_id - 1
        return record

    ids = list(range(scan_from, next_id))
    print(f"    scanning ids {scan_from}..{next_id - 1} ({len(ids)} ids)")

    if legacy:
        configs = {}
        silos = legacy_silos_for_ids(rpc_url, factory, ids)
    else:
        configs = configs_for_ids(rpc_url, factory, ids)
        silos = silos_for_configs(rpc_url, configs)

    discovered_ids = sorted(silos) if legacy else sorted(configs)

    existing_ids = {s["siloId"] for s in record.setdefault("silos", [])}
    added = 0
    for silo_id in discovered_ids:
        if silo_id in existing_ids:
            continue
        silo0, silo1 = silos.get(silo_id, (_common.ZERO_ADDRESS, _common.ZERO_ADDRESS))
        record["silos"].append(
            {
                "siloId": silo_id,
                "siloConfig": configs.get(silo_id, ""),
                "silo0": silo0,
                "silo1": silo1,
            }
        )
        added += 1

    record["silos"].sort(key=lambda s: s["siloId"])
    record["lastCheckedId"] = next_id - 1
    print(f"    added {added} new silo(s) (total {len(record['silos'])})")
    return record


def collect_silo_addresses(data: dict) -> list[str]:
    """Flat, order-preserving, deduped list of every non-zero silo0/silo1."""
    addrs: list[str] = []
    seen: set[str] = set()
    for factory in data.get("factories", {}).values():
        for entry in factory.get("silos", []):
            for key in ("silo0", "silo1"):
                addr = entry.get(key)
                if not addr or _common.is_zero_address(addr):
                    continue
                low = addr.lower()
                if low in seen:
                    continue
                seen.add(low)
                addrs.append(addr)
    return addrs


def fetch_metadata(rpc_url: str, silos: list[str]) -> dict[str, dict]:
    """Return {siloLower: {asset, symbol, decimals}} for the given silos.

    Two Multicall3 reads: asset() per silo, then symbol()+decimals() per unique asset.
    """
    asset_results = _common.aggregate3(rpc_url, [(s, _common.selector(ASSET_SIG)) for s in silos])
    silo_asset: dict[str, str] = {}
    for silo, (success, ret) in zip(silos, asset_results):
        silo_asset[silo] = _common.decode_address(ret) if success else _common.ZERO_ADDRESS

    unique_assets: list[str] = []
    seen_assets: set[str] = set()
    for silo in silos:
        asset = silo_asset[silo]
        if _common.is_zero_address(asset):
            continue
        if asset.lower() not in seen_assets:
            seen_assets.add(asset.lower())
            unique_assets.append(asset)

    asset_meta: dict[str, dict] = {}
    if unique_assets:
        calls: list[tuple[str, str]] = []
        for asset in unique_assets:
            calls.append((asset, _common.selector(SYMBOL_SIG)))
            calls.append((asset, _common.selector(DECIMALS_SIG)))
        results = _common.aggregate3(rpc_url, calls)
        for i, asset in enumerate(unique_assets):
            ok_symbol, ret_symbol = results[2 * i]
            ok_decimals, ret_decimals = results[2 * i + 1]
            asset_meta[asset.lower()] = {
                "symbol": decode_string(ret_symbol) if ok_symbol else "",
                "decimals": decode_uint(ret_decimals) if ok_decimals else 0,
            }

    out: dict[str, dict] = {}
    for silo in silos:
        asset = silo_asset[silo]
        am = asset_meta.get(asset.lower(), {"symbol": "", "decimals": 0})
        out[silo.lower()] = {"asset": asset, "symbol": am["symbol"], "decimals": am["decimals"]}
    return out


def build_silo_list(rpc_url: str, data: dict) -> None:
    """(Re)build the top-level `silos` array consumed by WithdrawFees.s.sol.

    A flat, deduped, human-readable list of objects:
        {"silo", "asset", "symbol", "decimals"}
    Asset metadata is immutable, so it is cached in this very list and only fetched for
    silos that are new since the last run. Keys are alphabetical so Foundry can decode the
    array straight into a struct. Per-market provenance (siloId/siloConfig/silo0/silo1)
    stays inside each factory's `silos[]` entry.
    """
    cached = {
        obj["silo"].lower(): obj
        for obj in data.get("silos", [])
        if isinstance(obj, dict) and obj.get("silo")
    }

    addresses = collect_silo_addresses(data)
    missing = [a for a in addresses if a.lower() not in cached]
    if missing:
        print(f"  metadata: fetching asset/symbol/decimals for {len(missing)} new silo(s)")
        fetched = fetch_metadata(rpc_url, missing)
    else:
        print("  metadata: up to date")
        fetched = {}

    silos: list[dict] = []
    for addr in addresses:
        low = addr.lower()
        meta = cached.get(low) or fetched.get(low, {})
        silos.append(
            {
                "silo": addr,
                "asset": meta.get("asset", _common.ZERO_ADDRESS),
                "symbol": meta.get("symbol", ""),
                "decimals": meta.get("decimals", 0),
            }
        )

    data["silos"] = silos
    # drop superseded shapes from older runs
    for legacy_key in ("siloIds", "siloSymbols", "siloDecimals", "siloMeta"):
        data.pop(legacy_key, None)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain", required=True, help="Chain alias, e.g. arbitrum_one")
    parser.add_argument("--rpc-url", required=True, help="RPC url for the chain")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        chain = _common.get_chain(args.chain)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    _common.activate_chain(chain.alias)

    out_path = _common.data_file(chain.alias)
    if not out_path.exists():
        print(f"ERROR: {out_path} not found. Run 1_collect_factories.py first.", file=sys.stderr)
        return 1

    data = json.loads(out_path.read_text(encoding="utf-8"))
    factories = data.get("factories", {})
    if not factories:
        print(f"[{chain.alias}] no factories on file, nothing to discover")
        return 0

    print(f"[{chain.alias}] discovering silos for {len(factories)} factory(ies)")

    for factory in list(factories):
        discover_factory(args.rpc_url, factory, factories[factory])
        # persist factory discovery after each one (incremental)
        out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # rebuild the consumable silo list (+ backfill immutable asset metadata) once
    build_silo_list(args.rpc_url, data)
    out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"[{chain.alias}] done. Total silos on file: {len(data['silos'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
