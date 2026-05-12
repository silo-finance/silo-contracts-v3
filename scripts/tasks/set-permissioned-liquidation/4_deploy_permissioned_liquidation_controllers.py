#!/usr/bin/env python3
"""
Run PermissionedLiquidationController deploy script for all markets from JSON.

Features:
- executes per-market forge script call with chain-specific RPC
- optional broadcast and verify flags
- verify is always skipped for: okx, injective, megaeth
- one failed market does not stop next markets
- prints end summary table in console
- extracts Hook/Gauge/ShareToken lines from forge output
- writes extracted setGauge data grouped by blockchain to JSON
- print-only mode to output ready commands without executing


python3 scripts/tasks/set-permissioned-liquidation/4_deploy_permissioned_liquidation_controllers.py --print

python3 scripts/tasks/set-permissioned-liquidation/4_deploy_permissioned_liquidation_controllers.py --broadcast
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = Path(__file__).resolve().parent

FORGE_SCRIPT_PATH = "silo-core/deploy/incentives-controller/PermissionedLiquidationControllerDeploy.s.sol"
SIC_DEPLOYMENTS_PATH = REPO_ROOT / "silo-core/deploy/incentives-controller/_siloIncentivesControllerDeployments.json"
SKIP_VERIFY_CHAINS = {"okx", "injective", "megaeth"}
CHAIN_GAS_ESTIMATE_MULTIPLIER: dict[str, int] = {
    "megaeth": 10000,
}
CHAIN_USE_SLOW_FLAG: set[str] = {
    "injective",
}

CHAIN_RPC_ENV_CANDIDATES: dict[str, list[str]] = {
    "arbitrum_one": ["RPC_ARBITRUM_ONE", "RPC_ARBITRUM"],
    "avalanche": ["RPC_AVALANCHE"],
    "base": ["RPC_BASE"],
    "bnb": ["RPC_BNB"],
    "injective": ["RPC_INJECTIVE"],
    "ink": ["RPC_INK"],
    "mainnet": ["RPC_MAINNET"],
    "mantle": ["RPC_MANTLE"],
    "megaeth": ["RPC_MEGAETH"],
    "okx": ["RPC_OKX"],
    "optimism": ["RPC_OPTIMISM"],
    "sonic": ["RPC_SONIC"],
    "xdc": ["RPC_XDC"],
}

SET_GAUGE_RE = re.compile(
    r"Hook\((0x[a-fA-F0-9]{40})\)\.setGauge\(\s*"
    r"gauge:\s*(0x[a-fA-F0-9]{40})\s*,\s*"
    r"(collateralShareToken|protectedShareToken|debtShareToken):\s*(0x[a-fA-F0-9]{40})\s*\)",
    re.MULTILINE,
)
ID_IN_KEY_RE = re.compile(r"\((\d+)\)")


@dataclass
class MarketRun:
    chain: str
    silo_config: str
    market_id: int | None
    success: bool
    skipped: bool
    exit_code: int
    error: str
    command: str


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
        return value[1:-1]
    return value


def load_repo_env(override_existing: bool = False) -> Path | None:
    candidates = [REPO_ROOT / "env", REPO_ROOT / ".env"]
    env_path = next((p for p in candidates if p.exists() and p.is_file()), None)
    if env_path is None:
        return None

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        value = _strip_quotes(value)
        if override_existing or key not in os.environ:
            os.environ[key] = value
    return env_path


def is_address(value: str) -> bool:
    value = value.strip()
    if not value.startswith("0x") or len(value) != 42:
        return False
    try:
        int(value[2:], 16)
    except ValueError:
        return False
    return True


def normalize_address(value: str) -> str:
    value = value.strip()
    if not is_address(value):
        raise ValueError(f"Invalid address: {value}")
    return value


def resolve_rpc_url(chain: str) -> tuple[str | None, str | None]:
    for env_name in CHAIN_RPC_ENV_CANDIDATES.get(chain, []):
        value = os.environ.get(env_name, "").strip()
        if value:
            return value, env_name
    return None, None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deploy permissioned liquidation controllers for current markets.")
    parser.add_argument(
        "--markets-json",
        default=str(SCRIPT_DIR / "v3_markets_by_chain.json"),
        help="Input markets JSON file.",
    )
    parser.add_argument(
        "--output-json",
        default=str(SCRIPT_DIR / "permissioned_liquidation_deploy_gauges_by_chain.json"),
        help="Output JSON with extracted hook/gauge/shareToken data.",
    )
    parser.add_argument(
        "--broadcast",
        action="store_true",
        help="Add --broadcast to forge script command.",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Add --verify to forge command where allowed (skipped for okx/injective/megaeth).",
    )
    parser.add_argument(
        "--print",
        dest="print_only",
        action="store_true",
        help="Print ready commands only; do not execute.",
    )
    parser.add_argument(
        "--chain",
        action="append",
        default=[],
        help="Optional chain filter (can be repeated).",
    )
    return parser.parse_args()


def load_markets(path: Path) -> dict[str, list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Markets JSON root must be an object.")

    out: dict[str, list[dict[str, Any]]] = {}
    for chain, markets in data.items():
        if not isinstance(chain, str) or not isinstance(markets, list):
            continue
        normalized: list[dict[str, Any]] = []
        for market in markets:
            if not isinstance(market, dict):
                continue
            addr = market.get("address")
            if not isinstance(addr, str):
                continue
            try:
                market["address"] = normalize_address(addr)
            except ValueError:
                continue
            normalized.append(market)
        out[chain] = normalized
    return out


def load_existing_sic_ids(path: Path) -> dict[str, set[int]]:
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        return {}

    out: dict[str, set[int]] = {}
    for chain, chain_obj in raw.items():
        if not isinstance(chain, str) or not isinstance(chain_obj, dict):
            continue
        ids: set[int] = set()
        for key in chain_obj.keys():
            if not isinstance(key, str):
                continue
            for match in ID_IN_KEY_RE.findall(key):
                try:
                    ids.add(int(match))
                except ValueError:
                    continue
        if ids:
            out[chain] = ids
    return out


def build_forge_command(
    chain: str,
    silo_config: str,
    rpc_url: str,
    *,
    broadcast: bool,
    verify: bool,
) -> list[str]:
    cmd = [
        "forge",
        "script",
        FORGE_SCRIPT_PATH,
        "--ffi",
        "--rpc-url",
        rpc_url,
    ]
    gas_multiplier = CHAIN_GAS_ESTIMATE_MULTIPLIER.get(chain.lower())
    if gas_multiplier is not None:
        cmd.extend(["--gas-estimate-multiplier", str(gas_multiplier)])
    if chain.lower() in CHAIN_USE_SLOW_FLAG:
        cmd.append("--slow")
    if broadcast:
        cmd.append("--broadcast")
    if verify and chain.lower() not in SKIP_VERIFY_CHAINS:
        cmd.append("--verify")
    return cmd


def command_to_display(
    *,
    silo_config: str,
    chain: str,
    rpc_env: str,
    broadcast: bool,
    verify_enabled: bool,
) -> str:
    chain_l = chain.lower()
    verify_note = ""
    if verify_enabled and chain_l in SKIP_VERIFY_CHAINS:
        verify_note = " # --verify skipped for this chain"

    cmd_parts = [
        "forge",
        "script",
        FORGE_SCRIPT_PATH,
        "--ffi",
        "--rpc-url",
        f"${rpc_env}",
    ]
    gas_multiplier = CHAIN_GAS_ESTIMATE_MULTIPLIER.get(chain_l)
    if gas_multiplier is not None:
        cmd_parts.extend(["--gas-estimate-multiplier", str(gas_multiplier)])
    if chain_l in CHAIN_USE_SLOW_FLAG:
        cmd_parts.append("--slow")
    if broadcast:
        cmd_parts.append("--broadcast")
    if verify_enabled and chain_l not in SKIP_VERIFY_CHAINS:
        cmd_parts.append("--verify")

    return (
        f"SILO_CONFIG={silo_config} DEBT=false FOUNDRY_PROFILE=core "
        + " ".join(cmd_parts)
        + verify_note
    )


def extract_set_gauge_data(output: str) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for hook, gauge, token_kind, share_token in SET_GAUGE_RE.findall(output):
        entries.append(
            {
                "hook": hook.lower(),
                "gauge": gauge.lower(),
                "shareToken": share_token.lower(),
                "shareTokenKind": token_kind,
            }
        )
    unique = {(e["hook"], e["gauge"], e["shareToken"], e["shareTokenKind"]): e for e in entries}
    return list(unique.values())


def load_progress_state(path: Path) -> dict[str, dict[str, dict[str, Any]]]:
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        return {}

    by_chain_raw: Any
    if "byChain" in raw and isinstance(raw.get("byChain"), dict):
        by_chain_raw = raw["byChain"]
    else:
        # backward compatibility: old format was {chain: [{siloConfig, entries}, ...]}
        by_chain_raw = raw

    out: dict[str, dict[str, dict[str, Any]]] = {}
    for chain, records in by_chain_raw.items():
        if not isinstance(chain, str) or not isinstance(records, list):
            continue
        chain_map: dict[str, dict[str, Any]] = {}
        for rec in records:
            if not isinstance(rec, dict):
                continue
            silo_cfg = rec.get("siloConfig")
            if not isinstance(silo_cfg, str):
                continue
            cfg_key = silo_cfg.lower()

            if "success" not in rec:
                # old record without status means previous successful extraction
                normalized = {
                    "siloConfig": cfg_key,
                    "id": rec.get("id") if isinstance(rec.get("id"), int) else None,
                    "success": True,
                    "exitCode": 0,
                    "error": "",
                    "command": "",
                    "entries": rec.get("entries") if isinstance(rec.get("entries"), list) else [],
                }
            else:
                entries = rec.get("entries") if isinstance(rec.get("entries"), list) else []
                recorded_success = bool(rec.get("success"))
                normalized = {
                    "siloConfig": cfg_key,
                    "id": rec.get("id") if isinstance(rec.get("id"), int) else None,
                    # Respect explicit saved status. If user/test tooling marked success=false,
                    # this entry must be retried and not auto-promoted to success.
                    "success": recorded_success,
                    "exitCode": rec.get("exitCode") if isinstance(rec.get("exitCode"), int) else 0,
                    "error": rec.get("error") if isinstance(rec.get("error"), str) else "",
                    "command": rec.get("command") if isinstance(rec.get("command"), str) else "",
                    "entries": entries,
                }
            chain_map[cfg_key] = normalized
        if chain_map:
            out[chain] = chain_map
    return out


def save_progress_state(path: Path, state: dict[str, dict[str, dict[str, Any]]]) -> None:
    by_chain: dict[str, list[dict[str, Any]]] = {}
    for chain, records_by_cfg in sorted(state.items(), key=lambda x: x[0]):
        records = list(records_by_cfg.values())
        records.sort(key=lambda r: ((r.get("id") is None), r.get("id") or 0, r["siloConfig"]))
        by_chain[chain] = records

    payload = {
        "formatVersion": 1,
        "byChain": by_chain,
    }
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_with_live_output(cmd: list[str], *, env: dict[str, str], cwd: Path) -> tuple[int, str]:
    """
    Run command, stream output live to console, and return full captured output.
    """
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    output_lines: list[str] = []
    assert proc.stdout is not None
    for line in proc.stdout:
        print(line, end="")
        output_lines.append(line)

    return_code = proc.wait()
    return return_code, "".join(output_lines)


def print_summary(results: list[MarketRun]) -> None:
    headers = ["chain", "id", "siloConfig", "status"]
    rows: list[list[str]] = []
    for r in results:
        if r.skipped:
            status = f"SKIPPED ({r.error or 'reason_not_set'})"
        else:
            status = "SUCCESS" if r.success else "FAIL"
        if not r.success and r.error:
            status = f"{status}: {r.error}"
        rows.append([r.chain, str(r.market_id) if r.market_id is not None else "-", r.silo_config, status])

    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    def fmt(row: list[str]) -> str:
        return " | ".join(cell.ljust(widths[i]) for i, cell in enumerate(row))

    print("\nSummary:")
    print(fmt(headers))
    print("-+-".join("-" * w for w in widths))
    for row in rows:
        print(fmt(row))


def main() -> int:
    args = parse_args()
    env_path = load_repo_env(override_existing=False)
    if env_path:
        print(f"[info] loaded env from {env_path}")

    markets_by_chain = load_markets(Path(args.markets_json))
    existing_sic_ids_by_chain = load_existing_sic_ids(SIC_DEPLOYMENTS_PATH)
    output_json_path = Path(args.output_json)
    output_json_path.parent.mkdir(parents=True, exist_ok=True)
    progress_state = load_progress_state(output_json_path)

    chain_filter = {c.strip().lower() for c in args.chain} if args.chain else set()

    commands_to_print: list[str] = []
    print_items: list[tuple[str, int | None, str, str]] = []
    results: list[MarketRun] = []
    total_markets = sum(
        len(markets)
        for chain, markets in markets_by_chain.items()
        if not chain_filter or chain.lower() in chain_filter
    )
    progress_idx = 0

    for chain, markets in sorted(markets_by_chain.items(), key=lambda x: x[0]):
        if chain_filter and chain.lower() not in chain_filter:
            continue

        rpc_url, rpc_env = resolve_rpc_url(chain)
        if not rpc_url:
            print(f"[warn] {chain}: missing RPC env, skipping chain")
            continue

        for market in markets:
            progress_idx += 1
            silo_config = market["address"]
            silo_config_lower = silo_config.lower()
            market_id = market.get("id") if isinstance(market.get("id"), int) else None
            cmd = build_forge_command(
                chain=chain,
                silo_config=silo_config,
                rpc_url=rpc_url,
                broadcast=args.broadcast,
                verify=args.verify and args.broadcast,
            )
            cmd_display = command_to_display(
                silo_config=silo_config,
                chain=chain,
                rpc_env=rpc_env,
                broadcast=args.broadcast,
                verify_enabled=args.verify and args.broadcast,
            )
            existing = progress_state.get(chain, {}).get(silo_config_lower)
            existing_failed = bool(existing) and not bool(existing.get("success"))
            in_sic_registry = (
                market_id is not None and market_id in existing_sic_ids_by_chain.get(chain, set())
            )

            if args.print_only:
                commands_to_print.append(cmd_display)
                if existing_failed:
                    status = "RETRY_FAILED_CACHE"
                elif in_sic_registry:
                    status = "ALREADY_IN_SIC_DEPLOYMENTS_JSON"
                elif existing and bool(existing.get("success")):
                    status = "DONE_SUCCESS"
                elif existing:
                    prev_error = str(existing.get("error") or "").strip()
                    status = f"PREV_FAIL ({prev_error})" if prev_error else "PREV_FAIL"
                else:
                    status = "PENDING"
                print_items.append((chain, market_id, cmd_display, status))
                continue

            if existing and bool(existing.get("success")):
                print()
                print("=" * 96)
                print(
                    f"[progress {progress_idx}/{total_markets}] "
                    f"chain={chain} silo_id={market_id if market_id is not None else '-'}"
                )
                print("=" * 96)
                print(f"[skip] already successful in progress file for config {silo_config_lower}")
                print()
                results.append(
                    MarketRun(
                        chain=chain,
                        silo_config=silo_config_lower,
                        market_id=market_id,
                        success=True,
                        skipped=True,
                        exit_code=0,
                        error="already_success_in_progress_json",
                        command=cmd_display,
                    )
                )
                continue

            # success=false should be treated as "no cache": rerun full flow.
            # Also remove stale record so current attempt fully replaces it.
            if existing_failed:
                progress_state.setdefault(chain, {}).pop(silo_config_lower, None)
                existing = None

            if in_sic_registry and not existing_failed:
                print()
                print("=" * 96)
                print(
                    f"[progress {progress_idx}/{total_markets}] "
                    f"chain={chain} silo_id={market_id if market_id is not None else '-'}"
                )
                print("=" * 96)
                print(
                    f"[skip] market id {market_id} already present in "
                    f"{SIC_DEPLOYMENTS_PATH}"
                )
                print()
                results.append(
                    MarketRun(
                        chain=chain,
                        silo_config=silo_config_lower,
                        market_id=market_id,
                        success=True,
                        skipped=True,
                        exit_code=0,
                        error="already_in_sic_deployments_json",
                        command=cmd_display,
                    )
                )
                continue

            env = os.environ.copy()
            env["SILO_CONFIG"] = silo_config
            env["DEBT"] = "false"
            env["FOUNDRY_PROFILE"] = "core"

            print()
            print("=" * 96)
            print(
                f"[progress {progress_idx}/{total_markets}] "
                f"chain={chain} silo_id={market_id if market_id is not None else '-'}"
            )
            print("=" * 96)
            print(f"[run] {cmd_display}")
            print()

            return_code, combined_output = run_with_live_output(cmd, env=env, cwd=REPO_ROOT)

            extracted = extract_set_gauge_data(combined_output)

            # Deployment is considered successful if we extracted setGauge payloads from logs.
            # This handles non-zero exits caused by verifier/post-deploy phases.
            success = (return_code == 0) or len(extracted) > 0
            error = ""
            if not success:
                lines = [ln.strip() for ln in combined_output.splitlines() if ln.strip()]
                error = lines[-1][:180] if lines else f"exit_code={return_code}"
            elif return_code != 0 and extracted:
                lines = [ln.strip() for ln in combined_output.splitlines() if ln.strip()]
                non_fatal = lines[-1][:180] if lines else f"exit_code={return_code}"
                error = f"non-fatal after deploy: {non_fatal}"

            progress_state.setdefault(chain, {})[silo_config_lower] = {
                "siloConfig": silo_config_lower,
                "id": market_id,
                "success": success,
                "exitCode": return_code,
                "error": error,
                "command": cmd_display,
                "entries": extracted,
            }
            # Persist after each command so reruns can resume immediately.
            save_progress_state(output_json_path, progress_state)

            results.append(
                MarketRun(
                    chain=chain,
                    silo_config=silo_config_lower,
                    market_id=market_id,
                    success=success,
                    skipped=False,
                    exit_code=return_code,
                    error=error,
                    command=cmd_display,
                )
            )

    if args.print_only:
        for i, (chain, market_id, cmd, status) in enumerate(print_items, start=1):
            market_id_text = str(market_id) if market_id is not None else "-"
            print(f"[{i}] chain: {chain}")
            print(f"silo id: {market_id_text}")
            print(f"status: {status}")
            print(f"command: {cmd}")
            print()
        print(f"\nPrinted commands: {len(commands_to_print)}")
        return 0

    save_progress_state(output_json_path, progress_state)
    print(f"\n[info] wrote extracted gauges JSON: {output_json_path}")

    print_summary(results)
    success_count = sum(1 for r in results if r.success)
    fail_count = len(results) - success_count
    skipped_count = sum(1 for r in results if r.skipped)
    print(
        f"\nTotal: {len(results)}, success: {success_count}, fail: {fail_count}, "
        f"skipped(already_success): {skipped_count}"
    )
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
