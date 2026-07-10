#!/usr/bin/env python3
"""Stage 3: withdraw fees for every silo with withdrawable revenue.

Three phases, all via Multicall3.aggregate3 (subcalls batched — not one RPC per silo):

  Phase 1 — probe: one withdrawFees() subcall per silo (batched) to find silos where
            withdraw would succeed (simulated eth_call, always runs).

  Phase 2 — amounts: for probe survivors only, four subcalls per silo in one aggregate:
            accrueInterest -> protocolFees (before) -> withdrawFees -> protocolFees (after)
            withdrawable = before - after (liquidity-capped, matches on-chain withdraw).

  Phase 3 — broadcast: optional cast send aggregate3 of withdrawFees() (--broadcast only).

Silos with withdrawable >= 0.001 token (decimals from data/<chain>.json) are included.

Usage:
  python3 silo-core/scripts/withdrawFees/3_withdraw_fees.py \\
      --chain arbitrum_one --rpc-url $RPC_ARBITRUM [--broadcast]
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import _common

ACCRUE_INTEREST_SIG = "accrueInterest()"
PROTOCOL_FEES_SIG = "protocolFees(address)"
WITHDRAW_FEES_SIG = "withdrawFees()"

# Multicall3 batch sizes (silos per eth_call, not RPC count per silo).
PROBE_SILOS_PER_BATCH = 100
AMOUNT_SILOS_PER_BATCH = 50
CALLS_PER_AMOUNT_PROBE = 4

# silos to never touch, keyed by chain id (mirrors WithdrawFees.s.sol)
BLACKLIST: dict[int, set[str]] = {
    42161: {"0xed9f6d6b4889424173e582f2c12c41791ddfdaca"},
}


def decode_uint(return_data: str) -> int:
    raw = return_data[2:] if return_data.startswith("0x") else return_data
    return int(raw, 16) if raw else 0


def format_amount(amount: int, decimals: int) -> str:
    if decimals <= 0:
        return str(amount)
    s = str(amount).rjust(decimals + 1, "0")
    return f"{s[:-decimals]}.{s[-decimals:]}"


@dataclass
class AssetRevenueTotal:
    symbol: str
    decimals: int
    amount: int = 0
    silo_count: int = 0


@dataclass
class PipelineStats:
    total_silos: int = 0
    blacklisted: int = 0
    probe_ok: int = 0
    probe_failed: int = 0
    amount_measured: int = 0
    amount_probe_failed: int = 0
    above_threshold: int = 0
    below_threshold: int = 0

    def probe_batches(self) -> int:
        probed = self.probe_ok + self.probe_failed
        if probed == 0:
            return 0
        return math.ceil(probed / PROBE_SILOS_PER_BATCH)

    def amount_batches(self) -> int:
        if self.probe_ok == 0:
            return 0
        return math.ceil(self.probe_ok / AMOUNT_SILOS_PER_BATCH)

    def as_dict(self) -> dict:
        return {
            "total_silos": self.total_silos,
            "blacklisted": self.blacklisted,
            "probe_ok": self.probe_ok,
            "probe_failed": self.probe_failed,
            "amount_measured": self.amount_measured,
            "amount_probe_failed": self.amount_probe_failed,
            "above_threshold": self.above_threshold,
            "below_threshold": self.below_threshold,
        }


def print_revenue_summary(chain_alias: str, totals: dict[str, AssetRevenueTotal], stats: PipelineStats) -> None:
    if not totals and stats.above_threshold == 0:
        return
    print("")
    print(f"[{chain_alias}] withdraw summary (withdrawable after liquidity cap, simulated):")
    print(
        f"  stats: {stats.total_silos} total, {stats.probe_ok} probe ok, "
        f"{stats.probe_failed} probe failed, {stats.above_threshold} above threshold"
    )
    for asset_key in sorted(totals, key=lambda k: totals[k].symbol):
        row = totals[asset_key]
        print(
            f"  {row.symbol}: {format_amount(row.amount, row.decimals)} "
            f"({row.silo_count} silo(s))"
        )


def summary_payload(
    chain_alias: str,
    silo_count: int,
    totals: dict[str, AssetRevenueTotal],
    stats: PipelineStats,
) -> dict:
    assets = []
    for asset_key in sorted(totals, key=lambda k: totals[k].symbol):
        row = totals[asset_key]
        assets.append(
            {
                "asset": asset_key,
                "symbol": row.symbol,
                "decimals": row.decimals,
                "amount_raw": row.amount,
                "amount": format_amount(row.amount, row.decimals),
                "silo_count": row.silo_count,
            }
        )
    return {
        "chain": chain_alias,
        "stats": stats.as_dict(),
        "silos_to_withdraw": silo_count,
        "assets": assets,
    }


def write_summary_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def aggregate_and_print_summaries(log_dir: Path, chains: list[str]) -> None:
    """Print per-chain withdraw revenue totals after all chains have been processed."""
    any_output = False
    for chain in chains:
        path = log_dir / f"{chain}.withdraw_summary.json"
        if not path.exists():
            print(f"[{chain}] (no withdraw summary — stage 3 may have failed or skipped)")
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        silo_count = payload.get("silos_to_withdraw", 0)
        assets = payload.get("assets", [])
        stats = payload.get("stats", {})
        print("")
        print(f"[{chain}] withdraw summary (withdrawable after liquidity cap, simulated):")
        if stats:
            print(
                f"  stats: {stats.get('total_silos', '?')} total, "
                f"{stats.get('probe_ok', '?')} probe ok, "
                f"{stats.get('probe_failed', '?')} probe failed, "
                f"{stats.get('above_threshold', '?')} above threshold"
            )
        print(f"  silos to withdraw: {silo_count}")
        if not assets:
            print("  (no assets above threshold)")
        else:
            for row in assets:
                print(
                    f"  {row['symbol']}: {row['amount']} "
                    f"({row['silo_count']} silo(s))"
                )
        any_output = True
    if not any_output:
        print("(no withdraw summaries found in log directory)")


def _withdraw_fees_calldata() -> str:
    return _common.selector(WITHDRAW_FEES_SIG)


def probe_withdraw_batch(
    rpc_url: str,
    silo_addresses: list[str],
) -> list[tuple[bool, str]]:
    """Phase 1: one withdrawFees() subcall per silo, batched via Multicall3."""
    withdraw = _withdraw_fees_calldata()
    results: list[tuple[bool, str]] = []
    for start in range(0, len(silo_addresses), PROBE_SILOS_PER_BATCH):
        chunk = silo_addresses[start:start + PROBE_SILOS_PER_BATCH]
        calls = [(silo, withdraw) for silo in chunk]
        results.extend(
            _common.aggregate3(rpc_url, calls, batch_size=PROBE_SILOS_PER_BATCH)
        )
    return results


def _amount_probe_calls(lens: str, silo: str) -> list[tuple[str, str]]:
    """Four subcalls per silo: accrue, fees before, withdraw, fees after."""
    fees_call = _common.encode_address_call(PROTOCOL_FEES_SIG, silo)
    withdraw = _withdraw_fees_calldata()
    return [
        (silo, _common.selector(ACCRUE_INTEREST_SIG)),
        (lens, fees_call),
        (silo, withdraw),
        (lens, fees_call),
    ]


def measure_withdrawable_batch(
    rpc_url: str,
    lens: str,
    silo_addresses: list[str],
) -> list[tuple[str, int | None]]:
    """Phase 2: withdrawable = protocolFees before - after (simulated in one aggregate).

    Returns (silo, withdrawable_raw) or (silo, None) on failed subcall sequence.
    """
    out: list[tuple[str, int | None]] = []

    for start in range(0, len(silo_addresses), AMOUNT_SILOS_PER_BATCH):
        chunk = silo_addresses[start:start + AMOUNT_SILOS_PER_BATCH]
        calls: list[tuple[str, str]] = []
        for silo in chunk:
            calls.extend(_amount_probe_calls(lens, silo))

        batch_results = _common.aggregate3(
            rpc_url,
            calls,
            batch_size=len(calls) or 1,
        )

        for i, silo in enumerate(chunk):
            base = i * CALLS_PER_AMOUNT_PROBE
            chunk_results = batch_results[base:base + CALLS_PER_AMOUNT_PROBE]
            if len(chunk_results) != CALLS_PER_AMOUNT_PROBE:
                out.append((silo, None))
                continue

            if not all(ok for ok, _ in chunk_results):
                out.append((silo, None))
                continue

            before = decode_uint(chunk_results[1][1])
            after = decode_uint(chunk_results[3][1])
            withdrawable = before - after if before >= after else 0
            out.append((silo, withdrawable))

    return out


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--aggregate-summaries",
        metavar="LOG_DIR",
        help="Print consolidated withdraw summaries from per-chain JSON files (orchestrator mode).",
    )
    parser.add_argument(
        "aggregate_chains",
        nargs="*",
        help="Chain aliases to include with --aggregate-summaries.",
    )
    parser.add_argument("--chain", help="Chain alias, e.g. arbitrum_one")
    parser.add_argument("--rpc-url", help="RPC url for the chain")
    parser.add_argument("--broadcast", action="store_true", help="Send the withdraw tx (otherwise dry-run)")
    parser.add_argument(
        "--summary-out",
        metavar="FILE",
        help="Write per-chain withdraw summary JSON (used by withdrawRevenue.sh).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.aggregate_summaries:
        if not args.aggregate_chains:
            print("ERROR: --aggregate-summaries requires at least one chain alias.", file=sys.stderr)
            return 1
        aggregate_and_print_summaries(Path(args.aggregate_summaries), args.aggregate_chains)
        return 0

    if not args.chain or not args.rpc_url:
        print("ERROR: --chain and --rpc-url are required unless using --aggregate-summaries.", file=sys.stderr)
        return 1

    try:
        chain = _common.get_chain(args.chain)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    _common.activate_chain(chain.alias)

    out_path = _common.data_file(chain.alias)
    if not out_path.exists():
        print(f"ERROR: {out_path} not found. Run stages 1 and 2 first.", file=sys.stderr)
        return 1

    data = json.loads(out_path.read_text(encoding="utf-8"))
    silos = data.get("silos", [])
    stats = PipelineStats(total_silos=len(silos))

    if not silos:
        print(f"[{chain.alias}] no silos on file, nothing to withdraw")
        if args.summary_out:
            write_summary_json(
                Path(args.summary_out),
                summary_payload(chain.alias, 0, {}, stats),
            )
        return 0

    lens = _common.deployment_address(chain.alias, "SiloLens.sol.json")
    blacklist = BLACKLIST.get(chain.chain_id, set())

    probe_entries: list[dict] = []
    for entry in silos:
        silo = entry["silo"]
        if silo.lower() in blacklist:
            stats.blacklisted += 1
            print(f"  skip {silo} - blacklisted")
            continue
        probe_entries.append(entry)

    print(
        f"[{chain.alias}] phase 1: probe withdrawFees for {len(probe_entries)} silo(s) "
        f"via Multicall3 (batch size {PROBE_SILOS_PER_BATCH})"
    )
    probe_addresses = [e["silo"] for e in probe_entries]
    probe_results = probe_withdraw_batch(args.rpc_url, probe_addresses)

    survivors: list[dict] = []
    for entry, (ok, _) in zip(probe_entries, probe_results):
        silo = entry["silo"]
        if ok:
            stats.probe_ok += 1
            survivors.append(entry)
        else:
            stats.probe_failed += 1

    print(
        f"[{chain.alias}] phase 1 probe: {len(probe_entries)} silo(s) in "
        f"{stats.probe_batches()} Multicall3 batch(es), {stats.probe_ok} ok, "
        f"{stats.probe_failed} failed (revert)"
    )

    to_withdraw: list[str] = []
    totals_by_asset: dict[str, AssetRevenueTotal] = {}

    if survivors:
        print(
            f"[{chain.alias}] phase 2: measure withdrawable for {len(survivors)} silo(s) "
            f"via Multicall3 (batch size {AMOUNT_SILOS_PER_BATCH}, "
            f"{CALLS_PER_AMOUNT_PROBE} subcalls/silo)"
        )
        survivor_addresses = [e["silo"] for e in survivors]
        amount_results = measure_withdrawable_batch(args.rpc_url, lens, survivor_addresses)

        for entry, (silo, withdrawable) in zip(survivors, amount_results):
            symbol = entry.get("symbol", "")
            decimals = int(entry.get("decimals", 0))
            asset = entry.get("asset", "")

            if withdrawable is None:
                stats.amount_probe_failed += 1
                print(f"  skip {silo} - amount probe failed (subcall revert)")
                continue

            stats.amount_measured += 1

            if withdrawable == 0:
                stats.below_threshold += 1
                continue

            withdraw_limit = 10 ** decimals // 1000
            if withdrawable < withdraw_limit:
                stats.below_threshold += 1
                print(
                    f"  skip {silo} {symbol} "
                    f"withdrawable={format_amount(withdrawable, decimals)} below threshold"
                )
                continue

            stats.above_threshold += 1
            asset_key = asset.lower() if asset else symbol.lower()
            if asset_key not in totals_by_asset:
                totals_by_asset[asset_key] = AssetRevenueTotal(symbol=symbol, decimals=decimals)
            totals_by_asset[asset_key].amount += withdrawable
            totals_by_asset[asset_key].silo_count += 1

            to_withdraw.append(silo)
            print(
                f"  WITHDRAW {silo} {symbol} "
                f"withdrawable={format_amount(withdrawable, decimals)}"
            )

        print(
            f"[{chain.alias}] phase 2 amounts: {len(survivors)} survivors in "
            f"{stats.amount_batches()} Multicall3 batch(es), {stats.amount_measured} measured, "
            f"{stats.amount_probe_failed} amount-probe failed, "
            f"{stats.above_threshold} above threshold, {stats.below_threshold} below"
        )

    print(f"[{chain.alias}] silos to withdraw: {len(to_withdraw)}")

    summary = summary_payload(chain.alias, len(to_withdraw), totals_by_asset, stats)
    if args.summary_out:
        write_summary_json(Path(args.summary_out), summary)
    else:
        print_revenue_summary(chain.alias, totals_by_asset, stats)

    if not to_withdraw:
        return 0

    return broadcast_withdrawals(args, chain.alias, to_withdraw)


def broadcast_withdrawals(args: argparse.Namespace, alias: str, silos: list[str]) -> int:
    withdraw_selector = _common.selector(WITHDRAW_FEES_SIG)
    tuples = ",".join(f"({silo},false,{withdraw_selector})" for silo in silos)
    multicall_arg = f"[{tuples}]"
    sig = "aggregate3((address,bool,bytes)[])"

    if not args.broadcast:
        print(f"[{alias}] dry-run: would withdraw from {len(silos)} silo(s) (pass --broadcast to send)")
        return 0

    private_key = _common.load_dotenv().get("PRIVATE_KEY", "")
    if not private_key:
        print(f"[{alias}] ERROR: PRIVATE_KEY not set in .env, cannot broadcast", file=sys.stderr)
        return 1

    print(f"[{alias}] broadcasting withdrawFees multicall for {len(silos)} silo(s)")
    cmd = [
        "cast", "send", _common.multicall3_for(alias), sig, multicall_arg,
        "--rpc-url", args.rpc_url,
        "--private-key", private_key,
    ]
    result = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        print(f"[{alias}] ERROR: cast send failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
