#!/usr/bin/env python3
"""Stage 2: discover every silo created by the factories in data/<chain>.json.

For each factory (collected by stage 1) it reads `getNextSiloId()`, determines the
starting silo id (cached, or probed among the known bases {1,100,101,3000,3001}),
then batch-reads `idToSiloConfig(id)` + `getSilos()` via Multicall3 and stores
{siloId, siloConfig, silo0, silo1} plus `lastCheckedId` for incremental reruns.

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

ID_TO_CONFIG_SIG = "idToSiloConfig(uint256)"
GET_SILOS_SIG = "getSilos()"

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


def silos_for_configs(rpc_url: str, configs: dict[int, str]) -> dict[int, tuple[str, str]]:
    """Return {siloId: (silo0, silo1)} by calling getSilos() on each config."""
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


def resolve_start_id(rpc_url: str, factory: str, next_id: int) -> int | None:
    """Probe known bases; return the resolved start id, or None if none found."""
    probes = [(probe, start) for probe, start in START_CANDIDATES if probe < next_id]
    if not probes:
        return None
    found = configs_for_ids(rpc_url, factory, [probe for probe, _ in probes])
    for probe, start in probes:
        if probe in found:
            return start
    return None


def discover_factory(rpc_url: str, factory: str, record: dict) -> dict:
    """Update `record` in place with discovered silos and return it."""
    try:
        next_id = _common.cast_call_uint(rpc_url, factory, "getNextSiloId()(uint256)")
    except RuntimeError:
        print(f"  {factory}: getNextSiloId() reverted - likely an old/incompatible factory, skipping")
        record["old"] = True
        return record

    print(f"  {factory}: nextSiloId={next_id}")

    if next_id <= 1:
        record["lastCheckedId"] = next_id - 1
        print("    no silos minted yet")
        return record

    last_checked = record.get("lastCheckedId")
    start_id = record.get("startId")

    if last_checked is not None and start_id is not None:
        scan_from = last_checked + 1
    else:
        start_id = resolve_start_id(rpc_url, factory, next_id)
        if start_id is None:
            record["lastCheckedId"] = next_id - 1
            print("    no start id among {1,100,101,3000,3001} - empty or old factory")
            return record
        record["startId"] = start_id
        scan_from = start_id

    if scan_from >= next_id:
        print("    up to date, nothing new")
        record["lastCheckedId"] = next_id - 1
        return record

    ids = list(range(scan_from, next_id))
    print(f"    scanning ids {scan_from}..{next_id - 1} ({len(ids)} ids)")

    configs = configs_for_ids(rpc_url, factory, ids)
    silos = silos_for_configs(rpc_url, configs)

    existing_ids = {s["siloId"] for s in record.setdefault("silos", [])}
    added = 0
    for silo_id in sorted(configs):
        if silo_id in existing_ids:
            continue
        silo0, silo1 = silos.get(silo_id, (_common.ZERO_ADDRESS, _common.ZERO_ADDRESS))
        record["silos"].append(
            {
                "siloId": silo_id,
                "siloConfig": configs[silo_id],
                "silo0": silo0,
                "silo1": silo1,
            }
        )
        added += 1

    record["silos"].sort(key=lambda s: s["siloId"])
    record["lastCheckedId"] = next_id - 1
    print(f"    added {added} new silo(s) (total {len(record['silos'])})")
    return record


def rebuild_flat_lists(data: dict) -> None:
    """Maintain the top-level `silos` address array consumed by WithdrawFees.s.sol.

    Flat, deduped (lowercased) list of every non-zero silo0/silo1 across all factories.
    Per-market `siloId` is intentionally kept only inside each factory's `silos[]` entry,
    where it is unambiguous (it is not unique across factories, so a flat list is useless).
    """
    silos: list[str] = []
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
                silos.append(addr)
    data["silos"] = silos
    data.pop("siloIds", None)  # drop legacy flat id array if present


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
        # persist after every factory (incremental)
        rebuild_flat_lists(data)
        out_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    total_silos = sum(len(f.get("silos", [])) for f in factories.values())
    print(f"[{chain.alias}] done. Total silos on file: {total_silos}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
