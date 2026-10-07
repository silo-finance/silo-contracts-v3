#!/usr/bin/env python3
"""
SiloVault market-removal loss list.

When a market is removed from a SiloVault's withdrawQueue while it still holds
assets, `totalAssets()` drops at that exact block, so every share holder at that
moment loses value pro-rata. This script produces a per-depositor loss list,
denominated in the vault's underlying asset.

Method (block-pinned, archive RPC required):
  - BEFORE = removal_block - 1 (state right before the removal tx)
  - AFTER  = removal_block     (state right after the removal tx)
  1. Enumerate every account that ever held vault shares from the ERC20 `Transfer`
     logs (deploy..BEFORE). Optionally use a subgraph instead (SUBGRAPH_URL env).
  2. Read `balanceOf` at BEFORE for every candidate; keep accounts with shares > 0.
  3. Completeness invariant (hard gate): sum(shares) == totalSupply() @BEFORE.
  4. Detect the removed market(s) as withdrawQueue@BEFORE minus withdrawQueue@AFTER,
     and compute L = sum(market.previewRedeem(market.balanceOf(vault))) @BEFORE.
  5. Per depositor:
       loss_previewdiff = vault.previewRedeem(shares) @BEFORE
                        - vault.previewRedeem(shares) @AFTER   (authoritative)
       loss_analytic    = shares * L / denominator              (cross-check)
     where denominator = totalSupply + 1e6 when fee == 0, otherwise it is derived
     from previewRedeem so that it matches the on-chain conversion (incl. fee shares).

Secrets are read ONLY from the environment (or a local, gitignored `.env` next to
this script). They must never be committed:
  - RPC_ARBITRUM / RPC_ARBITRUM_ONE / RPC_URL : archive RPC endpoint
  - SUBGRAPH_URL (optional) + THE_GRAPH_API_KEY (optional) : only if enumerating
    depositors via a subgraph instead of on-chain Transfer logs.

Non-secret parameters (vault address, removal block) are hardcoded below.

    python3 scripts/tasks/silo-vault-loss-list/snapshot_losses.py
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_SCRIPTS_DIR = Path(__file__).resolve().parents[2]
if str(REPO_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(REPO_SCRIPTS_DIR))

from rpc_multicall import multicall_eth_calls, rpc_request  # noqa: E402

# ----------------------------------------------------------------------------------
# Hardcoded (non-secret) configuration
# ----------------------------------------------------------------------------------
CHAIN = "arbitrum"
CHAIN_ID = 42161
VAULT = "0xd8c989aB5f5b2ABDc76a8D3Acec165300BF30ecD"
# Block at which the market removal (updateWithdrawQueue) was executed.
REMOVAL_BLOCK_B = 454834665

# 0 = auto-detect the vault deploy block via binary search over eth_getCode.
DEPLOY_BLOCK = 0

MULTICALL_BATCH = 300
LOGS_CHUNK = 5_000_000

OUTPUT_DIR = SCRIPT_DIR / "out"
OUTPUT_JSON = OUTPUT_DIR / "losses.json"

# RPC env var candidates, in priority order.
RPC_ENV_CANDIDATES = ["RPC_ARBITRUM", "RPC_ARBITRUM_ONE", "RPC_URL"]

# ERC20 Transfer(address,address,uint256) topic.
TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
ZERO_ADDRESS = "0x" + "0" * 40

# Function selectors (keccak256 of the signature, first 4 bytes).
SEL_BALANCE_OF = "0x70a08231"  # balanceOf(address)
SEL_TOTAL_SUPPLY = "0x18160ddd"  # totalSupply()
SEL_TOTAL_ASSETS = "0x01e1d114"  # totalAssets()
SEL_PREVIEW_REDEEM = "0x4cdad506"  # previewRedeem(uint256)
SEL_ASSET = "0x38d52e0f"  # asset()
SEL_DECIMALS = "0x313ce567"  # decimals()
SEL_SYMBOL = "0x95d89b41"  # symbol()
SEL_FEE = "0xddca3f43"  # fee()
SEL_WQ_LENGTH = "0x33f91ebb"  # withdrawQueueLength()
SEL_WQ = "0x62518ddf"  # withdrawQueue(uint256)
SEL_CONFIG = "0x0e68ec95"  # config(address)

# Decimal offset used by SiloVault for the virtual-shares conversion (1e6).
DECIMALS_OFFSET_POW = 10 ** 6


# ----------------------------------------------------------------------------------
# Environment / secrets
# ----------------------------------------------------------------------------------
def load_dotenv(path: Path) -> None:
    """Minimal .env loader; does not overwrite existing environment variables."""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def resolve_rpc_url() -> str:
    for name in RPC_ENV_CANDIDATES:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    raise SystemExit(
        "Missing RPC endpoint. Set one of "
        + ", ".join(RPC_ENV_CANDIDATES)
        + f" in the environment or in {SCRIPT_DIR / '.env'} (see .env.example)."
    )


# ----------------------------------------------------------------------------------
# Encoding / decoding helpers
# ----------------------------------------------------------------------------------
def norm(addr: str) -> str:
    return addr.strip().lower()


def enc_address(addr: str) -> str:
    return norm(addr).replace("0x", "").rjust(64, "0")


def enc_uint(value: int) -> str:
    return format(value, "x").rjust(64, "0")


def dec_uint(hex_result: str | None) -> int:
    if not hex_result or hex_result == "0x":
        return 0
    return int(hex_result, 16)


def dec_address(hex_result: str | None) -> str:
    if not hex_result or len(hex_result) < 42:
        return ZERO_ADDRESS
    return "0x" + hex_result[-40:]


def dec_string(hex_result: str | None) -> str:
    if not hex_result:
        return ""
    data = hex_result[2:] if hex_result.startswith("0x") else hex_result
    if len(data) < 128:
        # Fallback: bytes32-style packed string.
        try:
            return bytes.fromhex(data).split(b"\x00", 1)[0].decode("utf-8", "replace")
        except ValueError:
            return ""
    try:
        offset = int(data[0:64], 16) * 2
        length = int(data[offset:offset + 64], 16)
        start = offset + 64
        return bytes.fromhex(data[start:start + length * 2]).decode("utf-8", "replace")
    except (ValueError, UnicodeDecodeError):
        return ""


# ----------------------------------------------------------------------------------
# RPC wrappers
# ----------------------------------------------------------------------------------
def eth_call_single(rpc_url: str, to: str, data: str, block_hex: str) -> str | None:
    """Single eth_call pinned at a block; returns result hex or None."""
    body, err = rpc_request(
        rpc_url,
        "eth_call",
        [{"to": to, "data": data}, block_hex],
        timeout=120,
        chain=CHAIN,
    )
    if err or body is None or body.get("error"):
        return None
    result = body.get("result")
    return result if isinstance(result, str) else None


def multicall(rpc_url: str, calls: list[tuple[str, str]], block_hex: str) -> list[tuple[str | None, str | None]]:
    out: list[tuple[str | None, str | None]] = []
    for i in range(0, len(calls), MULTICALL_BATCH):
        chunk = calls[i:i + MULTICALL_BATCH]
        results, global_err = multicall_eth_calls(CHAIN, rpc_url, chunk, timeout=180, block_tag=block_hex)
        if global_err:
            raise SystemExit(f"multicall failed at block {block_hex}: {global_err}")
        out.extend(results)
    return out


def get_code(rpc_url: str, addr: str, block_hex: str) -> str:
    body, err = rpc_request(rpc_url, "eth_getCode", [addr, block_hex], timeout=60, chain=CHAIN)
    if err or body is None:
        return "0x"
    result = body.get("result")
    return result if isinstance(result, str) else "0x"


def find_deploy_block(rpc_url: str, addr: str, upper: int) -> int:
    """Binary-search the first block at which `addr` has bytecode."""
    if len(get_code(rpc_url, addr, hex(upper))) <= 2:
        raise SystemExit(f"No bytecode for {addr} at block {upper}")
    lo, hi = 0, upper
    while lo < hi:
        mid = (lo + hi) // 2
        if len(get_code(rpc_url, addr, hex(mid))) > 2:
            hi = mid
        else:
            lo = mid + 1
    return lo


def fetch_transfer_holders(rpc_url: str, from_block: int, to_block: int) -> list[str]:
    """Enumerate every address that ever sent or received vault shares (deploy..AFTER)."""
    candidates: set[str] = set()
    start = from_block
    chunk = LOGS_CHUNK
    while start <= to_block:
        end = min(start + chunk - 1, to_block)
        body, err = rpc_request(
            rpc_url,
            "eth_getLogs",
            [{
                "address": VAULT,
                "topics": [TRANSFER_TOPIC],
                "fromBlock": hex(start),
                "toBlock": hex(end),
            }],
            timeout=180,
            chain=CHAIN,
        )
        if err or body is None or body.get("error"):
            # Range too large for this provider: halve and retry.
            if chunk > 50_000:
                chunk //= 2
                continue
            msg = err or (body.get("error") if body else "empty")
            raise SystemExit(f"eth_getLogs failed [{start},{end}]: {msg}")
        for log in body.get("result", []):
            topics = log.get("topics", [])
            if len(topics) < 3:
                continue
            candidates.add("0x" + topics[1][-40:])
            candidates.add("0x" + topics[2][-40:])
        start = end + 1
    candidates.discard(ZERO_ADDRESS)
    return sorted(candidates)


def fetch_subgraph_holders(subgraph_url: str, api_key: str, block: int) -> list[str]:
    """Optional: enumerate depositors via the Silo subgraph `vaultPositions` entity."""
    query = (
        "query VaultDepositors($v:String!,$first:Int!,$skip:Int!){"
        " vaultPositions(block:{number:%d} first:$first skip:$skip"
        " where:{vault:$v, shares_gt:0}){ account{ id } } }" % block
    )
    import urllib.request

    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
    out: set[str] = set()
    skip = 0
    page = 1000
    while True:
        payload = json.dumps({"query": query, "variables": {"v": norm(VAULT), "first": page, "skip": skip}})
        req = urllib.request.Request(subgraph_url, data=payload.encode("utf-8"), headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if data.get("errors"):
            raise SystemExit(f"subgraph error: {data['errors']}")
        rows = data.get("data", {}).get("vaultPositions", [])
        if not rows:
            break
        for row in rows:
            out.add(norm(row["account"]["id"]))
        if len(rows) < page:
            break
        skip += page
    out.discard(ZERO_ADDRESS)
    return sorted(out)


# ----------------------------------------------------------------------------------
# Snapshot building
# ----------------------------------------------------------------------------------
def read_withdraw_queue(rpc_url: str, block_hex: str) -> list[str]:
    length = dec_uint(eth_call_single(rpc_url, VAULT, SEL_WQ_LENGTH, block_hex))
    if length == 0:
        return []
    calls = [(VAULT, SEL_WQ + enc_uint(i)) for i in range(length)]
    res = multicall(rpc_url, calls, block_hex)
    return [dec_address(data) if not err else ZERO_ADDRESS for data, err in res]


def market_config_enabled(rpc_url: str, market: str, block_hex: str) -> bool | None:
    result = eth_call_single(rpc_url, VAULT, SEL_CONFIG + enc_address(market), block_hex)
    if not result or len(result) < 2 + 64 * 2:
        return None
    data = result[2:]
    return int(data[64:128], 16) != 0


def main() -> int:
    load_dotenv(SCRIPT_DIR / ".env")
    rpc_url = resolve_rpc_url()

    block_after = REMOVAL_BLOCK_B
    block_before = REMOVAL_BLOCK_B - 1
    hex_before = hex(block_before)
    hex_after = hex(block_after)

    deploy_block = DEPLOY_BLOCK
    if deploy_block <= 0:
        print("[info] auto-detecting vault deploy block ...")
        deploy_block = find_deploy_block(rpc_url, VAULT, block_after)
    print(f"[info] vault={VAULT} chain={CHAIN} deploy_block={deploy_block}")
    print(f"[info] BEFORE={block_before} AFTER={block_after}")

    # 1. Enumerate candidate holders.
    subgraph_url = os.environ.get("SUBGRAPH_URL", "").strip()
    graph_key = os.environ.get("THE_GRAPH_API_KEY", "").strip()
    if subgraph_url and graph_key:
        print("[info] enumerating depositors via subgraph ...")
        candidates = fetch_subgraph_holders(subgraph_url, graph_key, block_before)
    else:
        print("[info] enumerating depositors via on-chain Transfer logs ...")
        candidates = fetch_transfer_holders(rpc_url, deploy_block, block_after)
    print(f"[info] {len(candidates)} candidate addresses")

    # 2. balanceOf at BEFORE -> holders with shares > 0.
    bal_calls = [(VAULT, SEL_BALANCE_OF + enc_address(a)) for a in candidates]
    bal_res = multicall(rpc_url, bal_calls, hex_before)
    holders: dict[str, int] = {}
    for addr, (data, err) in zip(candidates, bal_res):
        shares = dec_uint(data) if not err else 0
        if shares > 0:
            holders[addr] = shares
    shares_sum = sum(holders.values())
    print(f"[info] {len(holders)} holders with shares > 0; sum_shares={shares_sum}")

    # Vault-level reads.
    total_supply_before = dec_uint(eth_call_single(rpc_url, VAULT, SEL_TOTAL_SUPPLY, hex_before))
    total_supply_after = dec_uint(eth_call_single(rpc_url, VAULT, SEL_TOTAL_SUPPLY, hex_after))
    total_assets_before = dec_uint(eth_call_single(rpc_url, VAULT, SEL_TOTAL_ASSETS, hex_before))
    total_assets_after = dec_uint(eth_call_single(rpc_url, VAULT, SEL_TOTAL_ASSETS, hex_after))
    fee = dec_uint(eth_call_single(rpc_url, VAULT, SEL_FEE, hex_before))
    asset_addr = dec_address(eth_call_single(rpc_url, VAULT, SEL_ASSET, hex_after))
    asset_decimals = dec_uint(eth_call_single(rpc_url, asset_addr, SEL_DECIMALS, hex_after))
    asset_symbol = dec_string(eth_call_single(rpc_url, asset_addr, SEL_SYMBOL, hex_after))

    # 3. Completeness invariant (hard gate).
    invariant_ok = shares_sum == total_supply_before
    if not invariant_ok:
        raise SystemExit(
            "Completeness invariant FAILED: sum(shares)="
            f"{shares_sum} != totalSupply@BEFORE={total_supply_before} "
            f"(diff={total_supply_before - shares_sum}). Holder enumeration is incomplete."
        )
    print("[ok] completeness invariant holds: sum(shares) == totalSupply @BEFORE")

    # 4. Detect removed market(s) and compute L.
    wq_before = read_withdraw_queue(rpc_url, hex_before)
    wq_after = set(read_withdraw_queue(rpc_url, hex_after))
    removed_markets = [m for m in wq_before if m not in wq_after]
    if not removed_markets:
        raise SystemExit("No market was removed between BEFORE and AFTER; check REMOVAL_BLOCK_B.")
    if total_assets_after >= total_assets_before:
        raise SystemExit(
            f"totalAssets did not drop ({total_assets_before} -> {total_assets_after}); "
            "check REMOVAL_BLOCK_B."
        )

    removed_details: list[dict[str, Any]] = []
    total_lost = 0
    for market in removed_markets:
        market_shares = dec_uint(eth_call_single(rpc_url, market, SEL_BALANCE_OF + enc_address(VAULT), hex_before))
        assets = 0
        if market_shares > 0:
            assets = dec_uint(eth_call_single(rpc_url, market, SEL_PREVIEW_REDEEM + enc_uint(market_shares), hex_before))
        enabled_before = market_config_enabled(rpc_url, market, hex_before)
        enabled_after = market_config_enabled(rpc_url, market, hex_after)
        removed_details.append({
            "address": market,
            "vault_shares": str(market_shares),
            "assets": str(assets),
            "config_enabled_before": enabled_before,
            "config_enabled_after": enabled_after,
        })
        total_lost += assets
    print(f"[info] removed markets={len(removed_markets)} L={total_lost}")

    # Denominator for the analytic cross-check (matches previewRedeem conversion).
    if fee == 0:
        denominator = total_supply_before + DECIMALS_OFFSET_POW
        denominator_source = "totalSupply + 1e6 (fee == 0)"
    else:
        probe = total_supply_before
        pr_probe = dec_uint(eth_call_single(rpc_url, VAULT, SEL_PREVIEW_REDEEM + enc_uint(probe), hex_before))
        denominator = (probe * (total_assets_before + 1)) // pr_probe if pr_probe else (total_supply_before + DECIMALS_OFFSET_POW)
        denominator_source = "previewRedeem-derived (fee != 0)"

    # 5. Per-depositor loss.
    addrs = list(holders)
    pr_before = multicall(rpc_url, [(VAULT, SEL_PREVIEW_REDEEM + enc_uint(holders[a])) for a in addrs], hex_before)
    pr_after = multicall(rpc_url, [(VAULT, SEL_PREVIEW_REDEEM + enc_uint(holders[a])) for a in addrs], hex_after)

    depositors: list[dict[str, Any]] = []
    sum_loss = 0
    max_abs_cross_diff = 0
    for addr, (db, eb), (da, ea) in zip(addrs, pr_before, pr_after):
        value_before = dec_uint(db) if not eb else 0
        value_after = dec_uint(da) if not ea else 0
        loss_previewdiff = value_before - value_after
        if loss_previewdiff < 0:
            loss_previewdiff = 0
        loss_analytic = (holders[addr] * total_lost) // denominator if denominator else 0
        max_abs_cross_diff = max(max_abs_cross_diff, abs(loss_previewdiff - loss_analytic))
        sum_loss += loss_previewdiff
        depositors.append({
            "address": addr,
            "shares": str(holders[addr]),
            "value_before": str(value_before),
            "value_after": str(value_after),
            "loss_previewdiff": str(loss_previewdiff),
            "loss_analytic": str(loss_analytic),
        })

    depositors.sort(key=lambda d: int(d["loss_previewdiff"]), reverse=True)

    result = {
        "meta": {
            "description": "SiloVault market-removal loss list. Authoritative per-depositor loss is `loss_previewdiff` (assets).",
            "chain": CHAIN,
            "chain_id": CHAIN_ID,
            "vault": norm(VAULT),
            "removal_block": block_after,
            "block_before": block_before,
            "block_after": block_after,
            "deploy_block": deploy_block,
            "asset": {"address": asset_addr, "decimals": asset_decimals, "symbol": asset_symbol},
            "fee": str(fee),
            "denominator": str(denominator),
            "denominator_source": denominator_source,
            "total_supply_before": str(total_supply_before),
            "total_supply_after": str(total_supply_after),
            "total_supply_unchanged": total_supply_before == total_supply_after,
            "total_assets_before": str(total_assets_before),
            "total_assets_after": str(total_assets_after),
            "total_assets_drop": str(total_assets_before - total_assets_after),
            "removed_markets": removed_details,
            "L_total_lost": str(total_lost),
            "holders_count": len(holders),
            "shares_sum": str(shares_sum),
            "shares_sum_equals_total_supply": invariant_ok,
            "sum_loss_previewdiff": str(sum_loss),
            "reconciliation_dust": str(total_lost - sum_loss),
            "max_abs_previewdiff_minus_analytic": str(max_abs_cross_diff),
        },
        "depositors": depositors,
    }

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[ok] wrote {OUTPUT_JSON}")

    # Also emit the semicolon-separated CSV with the same per-depositor data.
    from to_csv import write_csv

    write_csv(OUTPUT_JSON, OUTPUT_DIR / "losses.csv")
    print(
        f"[done] holders={len(holders)} L={total_lost} sum_loss={sum_loss} "
        f"dust={total_lost - sum_loss} max_cross_diff={max_abs_cross_diff}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
