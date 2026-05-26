#!/usr/bin/env python3

# Usage: python3 silo-core/scripts/withdrawFees/withdrawRevenueRunner.py [--from INDEX] [--max-attempts MAX_ATTEMPTS] [--retry-delay-seconds SECONDS]
"""Withdraw fees runner with retries and final revenue summary."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path

WITHDRAW_SCRIPT = "silo-core/scripts/withdrawFees/WithdrawFees.s.sol"
TASKS: list[tuple[str, str]] = [
    ("0xAFd8F792cb025A76C4916652CfC8e20eee3b6fe2", "RPC_ARBITRUM"),
    ("0x504B8ca9C664AFe72324388122caBAFb72F9269f", "RPC_ARBITRUM"),
    ("0x384DC7759d35313F0b567D42bf2f611B285B657C", "RPC_ARBITRUM"),
    ("0xaE94617314381809C2a195fcDE469e7998132B40", "RPC_ARBITRUM"),
    ("0xf7dc975C96B434D436b9bF45E7a45c95F0521442", "RPC_ARBITRUM"),
    ("0x621Eacb756c7fa8bC0EA33059B881055d1693a33", "RPC_ARBITRUM"),
    ("0xb720078680Dc65B54568673410aBb81195E08122", "RPC_ARBITRUM"),
    ("0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0", "RPC_ARBITRUM"),
    ("0x51824653425e40Cd6253B71AcC8Def602A21427f", "RPC_ARBITRUM"),
    ("0xe376888fD6E5D5Afc12FEa0a8C18f283051c23aD", "RPC_ARBITRUM"),
    ("0xCb6CcBd979aa167b81411e672050c01826d715EC", "RPC_ARBITRUM"),
    ("0x8C1b49B1A45d9FD50c5846a6Cd19a5ADaA376B1B", "RPC_ARBITRUM"),
    ("0xb562b6CdEEE3ec10E4803B8dcfef81a32074e6B5", "RPC_ARBITRUM"),
    ("0x408822E4E8682413666809b0655161093cd36f2b", "RPC_ARBITRUM"),

    ("0x9e64f0CD206cce2Da5dE08E7F482D62F57013D0e", "RPC_AVALANCHE"),
    ("0x931e59f06b83dD3d9A622FD4537989B6C63B9bde", "RPC_AVALANCHE"),
    ("0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9", "RPC_AVALANCHE"),

    ("0xeB3C9fcE37A355df8f4a01CdaFA75b370607a21f", "RPC_BASE"),
    ("0x98F231070354F3a541081368b107155232CFfb1c", "RPC_BASE"),

    ("0x977e9b368E5aBEe020B5096A03cE6f78cb3439cf", "RPC_BNB"),
    ("0x1C7861978D11E9fd13257607d3FCf7bF3478f6EB", "RPC_BNB"),

    ("0x39021662EF7679845E6851E38E01912f556A861f", "RPC_INJECTIVE"),
    ("0xD2bf5845Ebc4d2b7966dD20Ad59Cb620F355A235", "RPC_INJECTIVE"),

    ("0xD13921239e3832FDC4141FDE544D3D058B529A5D", "RPC_INK"),

    ("0x1DAb4A310447185144467076b116DAC7aec3b48F", "RPC_MAINNET"),
    ("0x2534b2e33076787142246750E9340696267B96be", "RPC_MAINNET"),
    ("0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581", "RPC_MAINNET"),

    ("0xe5b39b0b2173caA82BaEa368952c6183cA2DA3Ac", "RPC_MANTLE"),

    ("0x95a7bC57c738C7f64103B93D04f49cbCa566afFD", "RPC_MEGAETH"),

    ("0x650b50E16A703e53A7944CCad513ad21670F0D09", "RPC_OKX"),
    ("0x1C7861978D11E9fd13257607d3FCf7bF3478f6EB", "RPC_OKX"),

    ("0x8ab5D81d342f14e594c65a6B33582b57e78E4a9d", "RPC_OPTIMISM"),
    ("0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5", "RPC_OPTIMISM"),
    ("0x55a4983949f8a3156Ad483c4003218a7F33D466b", "RPC_OPTIMISM"),
    ("0x8458396264bAaAfC9F6E6437a264636ce7c07c43", "RPC_OPTIMISM"),
    ("0xB25255036f210D7E32FC96e25460aB121FF0C25d", "RPC_OPTIMISM"),
    ("0x047801ED4F53Ad3dc28649ab972b3C949f27505c", "RPC_OPTIMISM"),
    ("0x4D43E78E669eD90bb125eF161F530E173f03834b", "RPC_OPTIMISM"),
    ("0x17B0FD3eB9CFbdA5B46A0C896e28b3F0c5a7F61d", "RPC_OPTIMISM"),
    ("0x01c6dc3bD8B175a9494F00b6D224b14EdC67CD34", "RPC_OPTIMISM"),
    ("0xb58B331b9cf46c597A34F9e198e8bB9ec5f17ADf", "RPC_OPTIMISM"),

    ("0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD", "RPC_SONIC"),
    ("0x55C5b74BC138C42dCb0deb206AE325a828Cd1372", "RPC_SONIC"),
    ("0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203", "RPC_SONIC"),
    ("0x89E3Cf1c67C0c0701EF7926A79f65EeEb52904eF", "RPC_SONIC"),
    ("0xa42001D6d2237d2c74108FE360403C4b796B7170", "RPC_SONIC"),

    ("0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD", "RPC_XDC"),
]

REVENUE_RE = re.compile(
    r"(\d+)\s+id daoAndDeployerRevenue in token\s+(\S+)\s+amount \(in asset decimals\)\s*:\s*([0-9][0-9_,]*(?:\.[0-9]+)?)"
)
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


@dataclass(frozen=True)
class TaskContext:
    rpc_var: str
    factory: str


class RunState:
    def __init__(self) -> None:
        self.current_context: TaskContext | None = None
        self.factories_without_silos: set[TaskContext] = set()
        self.revenue_by_silo: defaultdict[tuple[str, str, str], defaultdict[str, Decimal]] = defaultdict(
            lambda: defaultdict(Decimal)
        )
        self.revenue_by_chain_token: defaultdict[str, defaultdict[str, Decimal]] = defaultdict(
            lambda: defaultdict(Decimal)
        )

    @staticmethod
    def _clean_line(line: str) -> str:
        return ANSI_RE.sub("", line.rstrip("\n"))

    @staticmethod
    def _to_decimal(value: str) -> Decimal:
        normalized = value.replace(",", "").replace("_", "")
        return Decimal(normalized)

    def set_task_context(self, context: TaskContext) -> None:
        self.current_context = context

    def parse_output_line(self, line: str) -> None:
        clean = self._clean_line(line)

        if "No silos exist" in clean and self.current_context is not None:
            self.factories_without_silos.add(self.current_context)

        revenue_match = REVENUE_RE.search(clean)
        if revenue_match and self.current_context is not None:
            silo_id = revenue_match.group(1)
            token = revenue_match.group(2)
            raw_value = revenue_match.group(3)
            try:
                amount = self._to_decimal(raw_value)
            except InvalidOperation:
                return

            silo_key = (self.current_context.rpc_var, self.current_context.factory, silo_id)
            self.revenue_by_silo[silo_key][token] += amount
            self.revenue_by_chain_token[self.current_context.rpc_var][token] += amount


def load_dotenv(dotenv_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
            value = value[1:-1]
        values[key] = value
    return values


def run_task(index: int, context: TaskContext, repo_root: Path, env: dict[str, str], state: RunState) -> int:
    rpc_url = env.get(context.rpc_var, "")
    if not rpc_url:
        print(f"Task #{index} failed before execution: {context.rpc_var} is empty or unset.")
        print("Fix .env and rerun with:")
        print(
            "  python3 silo-core/scripts/withdrawFees/withdrawRevenueRunner.py "
            f"--from {index}"
        )
        return 1

    command = [
        "forge",
        "script",
        WITHDRAW_SCRIPT,
        "--ffi",
        "--rpc-url",
        rpc_url,
        # "--broadcast",
    ]
    cmd_for_copy = (
        "FOUNDRY_PROFILE=core "
        f"FACTORY={context.factory} forge script {WITHDRAW_SCRIPT} "
        f"--ffi --rpc-url ${context.rpc_var} --broadcast"
    )

    print("")
    print(
        f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] "
        f"Task #{index} | rpc={context.rpc_var} | FACTORY={context.factory}"
    )
    print(f"Command: {cmd_for_copy}")

    task_env = env.copy()
    task_env["FOUNDRY_PROFILE"] = "core"
    task_env["FACTORY"] = context.factory
    state.set_task_context(context)

    process = subprocess.Popen(
        command,
        cwd=str(repo_root),
        env=task_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None

    for line in process.stdout:
        print(line, end="")
        state.parse_output_line(line)

    return process.wait()


def print_summary(state: RunState, attempts_by_index: dict[int, int], success: bool) -> None:
    print("")
    print("========== WITHDRAW REVENUE SUMMARY ==========")
    print(f"Status: {'SUCCESS' if success else 'FAILED'}")

    if attempts_by_index:
        print("")
        print("Attempts per failed/retried task index:")
        for idx in sorted(attempts_by_index):
            print(f"  - Task #{idx}: {attempts_by_index[idx]} attempt(s)")

    print("")
    print("Factories without silos:")
    if state.factories_without_silos:
        for context in sorted(state.factories_without_silos, key=lambda item: (item.rpc_var, item.factory.lower())):
            print(f"  - rpc={context.rpc_var} factory={context.factory}")
    else:
        print("  - none")

    print("")
    print("Revenue per silo (rpc + factory + silo id):")
    if state.revenue_by_silo:
        for silo_key in sorted(state.revenue_by_silo, key=lambda key: (key[0], key[1].lower(), int(key[2]))):
            rpc_var, factory, silo_id = silo_key
            token_map = state.revenue_by_silo[silo_key]
            tokens_summary = ", ".join(f"{token}={amount}" for token, amount in sorted(token_map.items()))
            print(f"  - rpc={rpc_var} factory={factory} siloId={silo_id}: {tokens_summary}")
    else:
        print("  - no revenue entries detected in logs")

    print("")
    print("Total revenue per blockchain (rpc) and token:")
    if state.revenue_by_chain_token:
        for rpc_var in sorted(state.revenue_by_chain_token):
            print(f"  - {rpc_var}:")
            token_map = state.revenue_by_chain_token[rpc_var]
            for token, amount in sorted(token_map.items()):
                print(f"      {token}: {amount}")
    else:
        print("  - no revenue entries detected in logs")

    print("==============================================")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run withdraw fees directly with retries and summary."
    )
    parser.add_argument(
        "--from",
        dest="from_index",
        type=int,
        default=0,
        help="Initial task index to start from (0-based).",
    )
    parser.add_argument(
        "--max-attempts",
        type=int,
        default=3,
        help="Maximum attempts per failing task index (including first attempt).",
    )
    parser.add_argument(
        "--retry-delay-seconds",
        type=int,
        default=30,
        help="Delay before retrying the same failed index.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.from_index < 0:
        print("--from must be >= 0", file=sys.stderr)
        return 1
    if args.from_index >= len(TASKS):
        print(f"--from index {args.from_index} is out of range (max: {len(TASKS) - 1})", file=sys.stderr)
        return 1
    if args.max_attempts < 1:
        print("--max-attempts must be >= 1", file=sys.stderr)
        return 1
    if args.retry_delay_seconds < 0:
        print("--retry-delay-seconds must be >= 0", file=sys.stderr)
        return 1

    script_path = Path(__file__).resolve()
    repo_root = script_path.parents[3]
    dotenv_path = repo_root / ".env"
    if not dotenv_path.exists():
        print(f"Cannot find .env in expected repository root: {repo_root}", file=sys.stderr)
        return 1

    env = os.environ.copy()
    env.update(load_dotenv(dotenv_path))

    state = RunState()
    attempts_by_index: defaultdict[int, int] = defaultdict(int)
    index = args.from_index

    while index < len(TASKS):
        factory, rpc_var = TASKS[index]
        context = TaskContext(rpc_var=rpc_var, factory=factory)

        exit_code = run_task(index=index, context=context, repo_root=repo_root, env=env, state=state)
        if exit_code == 0:
            index += 1
            continue

        attempts_by_index[index] += 1
        if attempts_by_index[index] >= args.max_attempts:
            print("")
            print(f"Task #{index} failed.")
            print(f"Stopping after {attempts_by_index[index]} failed attempt(s) for Task #{index}.")
            print_summary(state=state, attempts_by_index=dict(attempts_by_index), success=False)
            return 1

        print("")
        print(
            f"Task #{index} failed (attempt {attempts_by_index[index]}/{args.max_attempts}). "
            f"Retrying in {args.retry_delay_seconds}s..."
        )
        time.sleep(args.retry_delay_seconds)

    print("")
    print("All tasks completed successfully.")
    print_summary(state=state, attempts_by_index=dict(attempts_by_index), success=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
