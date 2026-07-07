#!/usr/bin/env python3
"""Stage 3: withdraw fees for every silo with withdrawable revenue.

Reads data/<chain>.json (built by stages 1-2), then in a single Multicall3.aggregate3
eth_call per batch reads, for every silo:
    accrueInterest() -> protocolFees() -> getFeesAndFeeReceivers() -> getLiquidity()
accrueInterest runs first inside the same (simulated, never broadcast) multicall so the
following reads reflect pending interest. It then decides which silos clear the 0.01-token
threshold and broadcasts a single Multicall3.aggregate3 of withdrawFees() with cast send.

This is the Python replacement for the old forge script: it avoids forge's local fork and
its lazy slot-by-slot state fetching, so it runs in seconds instead of minutes.

Usage:
  python3 silo-core/scripts/withdrawFees/3_withdraw_fees.py \
      --chain arbitrum_one --rpc-url $RPC_ARBITRUM [--broadcast]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

import _common

ACCRUE_INTEREST_SIG = "accrueInterest()"
PROTOCOL_FEES_SIG = "protocolFees(address)"
FEES_AND_RECEIVERS_SIG = "getFeesAndFeeReceivers(address)"
GET_LIQUIDITY_SIG = "getLiquidity()"
WITHDRAW_FEES_SIG = "withdrawFees()"

READS_PER_SILO = 4  # accrueInterest, protocolFees, getFeesAndFeeReceivers, getLiquidity
SILOS_PER_BATCH = 50  # keep each silo's 4 calls together and the eth_call gas sane

# silos to never touch, keyed by chain id (mirrors WithdrawFees.s.sol)
BLACKLIST: dict[int, set[str]] = {
    42161: {"0xed9f6d6b4889424173e582f2c12c41791ddfdaca"},
}


def decode_uint(return_data: str) -> int:
    raw = return_data[2:] if return_data.startswith("0x") else return_data
    return int(raw, 16) if raw else 0


def decode_fees_and_receivers(return_data: str) -> tuple[str, str, int, int]:
    """Decode (address daoFeeReceiver, address deployerFeeReceiver, uint daoFee, uint deployerFee)."""
    raw = return_data[2:] if return_data.startswith("0x") else return_data
    if len(raw) < 256:
        return _common.ZERO_ADDRESS, _common.ZERO_ADDRESS, 0, 0
    dao_receiver = "0x" + raw[24:64]
    deployer_receiver = "0x" + raw[88:128]
    dao_fee = int(raw[128:192], 16)
    deployer_fee = int(raw[192:256], 16)
    return dao_receiver, deployer_receiver, dao_fee, deployer_fee


def preview_revenue(earned_fees: int, liquidity: int, dao_fee: int, deployer_fee: int, deployer_receiver: str):
    """Port of Silo._withdrawFeesPreview (DAO_REVENUE rounds up)."""
    if earned_fees > liquidity:
        earned_fees = liquidity
    if earned_fees == 0:
        return 0, 0

    dao_revenue = earned_fees
    deployer_revenue = 0
    if not _common.is_zero_address(deployer_receiver):
        total = dao_fee + deployer_fee
        if total > 0:
            dao_revenue = (earned_fees * dao_fee + total - 1) // total  # mulDiv, Rounding.Ceil
        deployer_revenue = earned_fees - dao_revenue
    return dao_revenue, deployer_revenue


def format_amount(amount: int, decimals: int) -> str:
    if decimals <= 0:
        return str(amount)
    s = str(amount).rjust(decimals + 1, "0")
    return f"{s[:-decimals]}.{s[-decimals:]}"


def gather_reads(rpc_url: str, lens: str, silos: list[dict]) -> list[tuple[bool, str]]:
    """One aggregate3 per chunk of silos; returns flat results (READS_PER_SILO per silo)."""
    results: list[tuple[bool, str]] = []
    for start in range(0, len(silos), SILOS_PER_BATCH):
        chunk = silos[start:start + SILOS_PER_BATCH]
        calls: list[tuple[str, str]] = []
        for entry in chunk:
            silo = entry["silo"]
            calls.append((silo, _common.selector(ACCRUE_INTEREST_SIG)))
            calls.append((lens, _common.encode_address_call(PROTOCOL_FEES_SIG, silo)))
            calls.append((lens, _common.encode_address_call(FEES_AND_RECEIVERS_SIG, silo)))
            calls.append((silo, _common.selector(GET_LIQUIDITY_SIG)))
        # batch_size large enough so a chunk is a single eth_call (keeps accrueInterest + reads together)
        results.extend(_common.aggregate3(rpc_url, calls, batch_size=len(calls) or 1))
    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain", required=True, help="Chain alias, e.g. arbitrum_one")
    parser.add_argument("--rpc-url", required=True, help="RPC url for the chain")
    parser.add_argument("--broadcast", action="store_true", help="Send the withdraw tx (otherwise dry-run)")
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
        print(f"ERROR: {out_path} not found. Run stages 1 and 2 first.", file=sys.stderr)
        return 1

    data = json.loads(out_path.read_text(encoding="utf-8"))
    silos = data.get("silos", [])
    if not silos:
        print(f"[{chain.alias}] no silos on file, nothing to withdraw")
        return 0

    lens = _common.deployment_address(chain.alias, "SiloLens.sol.json")
    blacklist = BLACKLIST.get(chain.chain_id, set())

    print(f"[{chain.alias}] reading revenue for {len(silos)} silo(s) via Multicall3 (lens {lens})")
    reads = gather_reads(args.rpc_url, lens, silos)

    to_withdraw: list[str] = []
    total_by_symbol: dict[str, int] = {}

    for i, entry in enumerate(silos):
        silo = entry["silo"]
        decimals = int(entry.get("decimals", 0))
        symbol = entry.get("symbol", "")

        if silo.lower() in blacklist:
            continue

        base = i * READS_PER_SILO
        # reads[base] is accrueInterest (state-priming only)
        ok_fees, fees_data = reads[base + 1]
        ok_recv, recv_data = reads[base + 2]
        ok_liq, liq_data = reads[base + 3]

        if not (ok_fees and ok_recv and ok_liq):
            print(f"  skip {silo} - a read call reverted")
            continue

        dao_and_deployer_revenue = decode_uint(fees_data)
        if dao_and_deployer_revenue == 0:
            continue

        _, deployer_receiver, dao_fee, deployer_fee = decode_fees_and_receivers(recv_data)
        liquidity = decode_uint(liq_data)

        dao_revenue, deployer_revenue = preview_revenue(
            dao_and_deployer_revenue, liquidity, dao_fee, deployer_fee, deployer_receiver
        )
        if dao_revenue == 0 and deployer_revenue == 0:
            continue

        withdraw_limit = 10 ** decimals // 100
        if dao_revenue < withdraw_limit and deployer_revenue < withdraw_limit:
            print(
                f"  skip {silo} {symbol} "
                f"dao={format_amount(dao_revenue, decimals)} dep={format_amount(deployer_revenue, decimals)}"
            )
            continue

        total = dao_revenue + deployer_revenue
        total_by_symbol[symbol] = total_by_symbol.get(symbol, 0) + total
        to_withdraw.append(silo)
        print(f"  WITHDRAW {silo} {symbol} amount={format_amount(total, decimals)}")

    print(f"[{chain.alias}] silos to withdraw: {len(to_withdraw)}")
    for symbol, amount in total_by_symbol.items():
        print(f"  total {symbol}: {amount} (raw)")

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
        "cast", "send", _common.MULTICALL3, sig, multicall_arg,
        "--rpc-url", args.rpc_url,
        "--private-key", private_key,
    ]
    result = subprocess.run(cmd, text=True, capture_output=True)
    # never echo argv (it contains the key); only stdout/stderr
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        print(f"[{alias}] ERROR: cast send failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
