# SiloVault market-removal loss list

Produces a per-depositor loss list for a SiloVault after a market was removed from
its `withdrawQueue` while it still held assets. Removing such a market instantly
drops `totalAssets()` (it only sums markets currently in the queue), so every share
holder at that block loses value pro-rata. The output of this tool is consumed by a
separate distribution/airdrop tool; distribution itself is out of scope here.

## What it computes

- `BEFORE = removal_block - 1`, `AFTER = removal_block`.
- Enumerates every account that ever held vault shares from on-chain ERC20
  `Transfer` logs, then reads `balanceOf` at `BEFORE` and keeps holders with
  `shares > 0`.
- Hard completeness gate: `sum(shares) == totalSupply() @BEFORE` (exact wei).
- Auto-detects the removed market(s) as `withdrawQueue@BEFORE \ withdrawQueue@AFTER`
  and computes `L = sum(market.previewRedeem(market.balanceOf(vault))) @BEFORE`.
- Per depositor:
  - `loss_previewdiff = previewRedeem(shares)@BEFORE - previewRedeem(shares)@AFTER`
    (authoritative; the actual redeemable-value drop, in asset units).
  - `loss_analytic = shares * L / denominator` (independent cross-check), where
    `denominator = totalSupply + 1e6` when `fee == 0`, otherwise derived from
    `previewRedeem` so it matches the on-chain conversion including fee shares.

The two measures agree to within a couple of wei; `sum(loss_previewdiff)` reconciles
to `L` minus a few wei of virtual-share/rounding dust (reported in the output).

## Configuration

Non-secret parameters are hardcoded at the top of `snapshot_losses.py`:

- `VAULT` – vault address.
- `REMOVAL_BLOCK_B` – block at which the removal (`updateWithdrawQueue`) executed.
- `DEPLOY_BLOCK` – `0` to auto-detect via binary search over `eth_getCode`.

Secrets are read only from the environment or a local, gitignored `.env`:

- `RPC_ARBITRUM` / `RPC_ARBITRUM_ONE` / `RPC_URL` – archive RPC (historical
  `eth_call` / `eth_getLogs`). The first non-empty one is used.
- `SUBGRAPH_URL` + `THE_GRAPH_API_KEY` – optional. If both are set, depositors are
  enumerated via the subgraph `vaultPositions` entity instead of Transfer logs.

Provide them either by exporting in your shell, or by creating a local, gitignored
`.env` next to this script (the repo ignores all `.env*` files, so it is never
committed):

```bash
# scripts/tasks/silo-vault-loss-list/.env
RPC_ARBITRUM=https://your-archive-arbitrum-rpc
```

> Note on enumeration source: at the time of writing, no public Silo subgraph for
> Arbitrum One indexes the required block, so on-chain `Transfer`-log enumeration is
> the default. It is self-validating via the completeness invariant above and needs
> only the archive RPC. The subgraph path remains available via `SUBGRAPH_URL`.

## Usage

```bash
# Generate out/losses.json and out/losses.csv:
python3 scripts/tasks/silo-vault-loss-list/snapshot_losses.py

# Regenerate the CSV from an existing JSON only:
python3 scripts/tasks/silo-vault-loss-list/to_csv.py
```

No external Python dependencies (standard library only). The script reuses
`scripts/rpc_multicall.py` for Multicall3 batching.

## Output

- `out/losses.json` – `meta` block (chain, vault, blocks, asset, totals, removed
  markets, `L`, reconciliation stats) plus a `depositors` array of
  `{ address, shares, value_before, value_after, loss_previewdiff, loss_analytic }`,
  sorted by loss descending. All amounts are raw integer strings.
- `out/losses.csv` – the same per-depositor rows, semicolon (`;`) separated.

`loss_previewdiff` is the authoritative loss amount (in the vault asset, raw units).
