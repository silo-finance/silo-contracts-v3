#!/usr/bin/env python3
"""Forge-based withdraw revenue runner (one forge script run per factory).

Reads factories.json (a plain array) and invokes WithdrawFees.s.sol with FACTORY
and START_SILO_ID. Stops on the first forge failure and prints a resume command.

--from-id is the 0-based index into the factories array.

Usage:
  python3 silo-core/scripts/withdrawFeesForge/run_withdraw_revenue.py
  python3 silo-core/scripts/withdrawFeesForge/run_withdraw_revenue.py | grep --line-buffered -iE 'WITHDRAWING|error|\[FAILED\]|\[OK\]|id=' 
  python3 silo-core/scripts/withdrawFeesForge/run_withdraw_revenue.py --broadcast
  python3 silo-core/scripts/withdrawFeesForge/run_withdraw_revenue.py --from-id 13
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections import deque
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FORGE_SCRIPT = "silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol"
FACTORIES_FILE = SCRIPT_DIR / "factories.json"
TAIL_LINES = 30

CHAIN_RPC_ENV: dict[str, str] = {
    "arbitrum_one": "RPC_ARBITRUM",
    "avalanche": "RPC_AVALANCHE",
    "base": "RPC_BASE",
    "bnb": "RPC_BNB",
    "injective": "RPC_INJECTIVE",
    "ink": "RPC_INK",
    "mainnet": "RPC_MAINNET",
    "mantle": "RPC_MANTLE",
    "megaeth": "RPC_MEGAETH",
    "okx": "RPC_OKX",
    "optimism": "RPC_OPTIMISM",
    "sonic": "RPC_SONIC",
    "xdc": "RPC_XDC",
}


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
    return SCRIPT_DIR.parents[3]


def load_dotenv(dotenv_path: Path | None = None) -> dict[str, str]:
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
            line = line[len("export ") :].strip()
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


def load_factories() -> list[dict]:
    payload = json.loads(FACTORIES_FILE.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or not payload:
        raise SystemExit(f"No factories found in {FACTORIES_FILE}")
    return payload


def resume_command(from_id: int, broadcast: bool) -> str:
    script = "python3 silo-core/scripts/withdrawFeesForge/run_withdraw_revenue.py"
    args = f" --from-id {from_id}"
    if broadcast:
        args += " --broadcast"
    return script + args


def run_forge(
    factory_entry: dict,
    rpc_url: str,
    broadcast: bool,
    cwd: Path,
) -> tuple[int, deque[str]]:
    env = os.environ.copy()
    env["FOUNDRY_PROFILE"] = "core"
    env["FACTORY"] = factory_entry["factory"]
    env["START_SILO_ID"] = str(factory_entry["startSiloId"])

    cmd = [
        "forge",
        "script",
        FORGE_SCRIPT,
        "--ffi",
        "--rpc-url",
        rpc_url,
    ]
    if broadcast:
        cmd.append("--broadcast")

    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    tail: deque[str] = deque(maxlen=TAIL_LINES)
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        tail.append(line.rstrip("\n"))

    return proc.wait(), tail


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run WithdrawFees.s.sol for every factory in factories.json."
    )
    parser.add_argument(
        "--broadcast",
        action="store_true",
        help="Broadcast transactions (default is dry-run / simulation only).",
    )
    parser.add_argument(
        "--from-id",
        type=int,
        default=0,
        metavar="N",
        help="Array index to start from (0-based). Default: 0.",
    )
    args = parser.parse_args()

    factories = load_factories()
    total = len(factories)

    if args.from_id < 0 or args.from_id >= total:
        print(
            f"error: --from-id must be between 0 and {total - 1} (got {args.from_id})",
            file=sys.stderr,
        )
        return 1

    env_values = load_dotenv()
    root = repo_root()
    mode = "broadcast" if args.broadcast else "dry-run"
    remaining = total - args.from_id

    print(
        f"Running {remaining}/{total} factories ({mode}), "
        f"starting from index={args.from_id}"
    )
    print()

    for index, entry in enumerate(factories):
        if index < args.from_id:
            continue

        chain = entry["chain"]
        rpc_env = CHAIN_RPC_ENV.get(chain)
        if rpc_env is None:
            print(f"[FAILED] index={index}: unknown chain '{chain}'", file=sys.stderr)
            return 1

        rpc_url = env_values.get(rpc_env, "")
        if not rpc_url:
            print(f"[FAILED] index={index}: {rpc_env} is not set in .env", file=sys.stderr)
            return 1

        print(
            f"index={index} ({index + 1}/{total}) | {chain} | "
            f"factory {entry['factory']} | startSiloId={entry['startSiloId']}"
        )
        print(f"Starting forge script ({mode})...")
        print()

        returncode, tail = run_forge(entry, rpc_url, args.broadcast, root)

        print()
        if returncode != 0:
            print(
                f"[FAILED] index={index} | {chain} | factory {entry['factory']}"
            )
            print()
            print("Last lines of output:")
            for line in tail:
                print(line)
            print()
            print("Resume from this factory:")
            print(f"  {resume_command(index, False)}")
            print(f"  {resume_command(index, True)}")
            return 1

        print(f"[OK] index={index} completed")
        print()

    print(f"{remaining}/{total} factories completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
