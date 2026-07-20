# Migrate Liquidation Helpers

Reusable per-chain toolkit for redeploying `LiquidationHelper` / `ManualLiquidationHelper`
and updating `ALLOWED_ROLE` on hooks and `PermissionedLiquidationController`s.

## Sources

| Data | Source |
|------|--------|
| Markets (`siloConfig`) | `silo-core/deploy/silo/_siloDeployments.json` |
| **NEW** helpers | `silo-core/deployments/<chain>/*LiquidationHelper*.json` (disk) |
| **OLD** helpers | previous distinct address from `git log -- <file>` (not `HEAD~1`) |

## Order of operations (per chain)

1. **Deploy** (overwrites deployment JSON files):
   - `PermissionedLiquidationControllerFactoryDeploy` (factory only; existing controllers unchanged)
   - `LiquidationHelperDeploy` with each needed `AGGREGATOR`
   - `ManualLiquidationHelperDeploy`
2. **Discover** on-chain whitelist state + OLD/NEW helpers:
   ```bash
   python3 scripts/tasks/migrate-liquidation-helpers/1_discover_whitelists.py --chain mainnet
   ```
   Writes `out/inventory_<chain>.json` (includes helper OLD/NEW pairs). Checks hook **and**
   controller whitelists (both can apply). Includes `VERSION()` for hooks/controllers and
   human-readable `totalAssets` (via asset decimals). Warns on public markets.
3. **Build Safe batches** (revoke OLD + grant NEW per owner):
   ```bash
   python3 scripts/tasks/migrate-liquidation-helpers/2_build_migration_batches.py --chain mainnet
   ```
   Default: only hook/controller contracts that already have a non-empty `ALLOWED_ROLE`
   whitelist (from inventory). Public / empty whitelists are skipped.
   Writes `out/Migrate Liquidation Helpers - <chain> - <ownerShort>[ - Part N].json`.
4. **Whitelist bots on NEW helpers** (same `PRIVATE_KEY` as helper deployer):
   ```bash
   FOUNDRY_PROFILE=core \
     forge script silo-core/deploy/liquidationHelper/WhitelistLiquidationHelpers.s.sol \
     --ffi --rpc-url $RPC_MAINNET --broadcast
   ```
5. **Fork-replay** each Safe JSON before importing to the Safe:
   ```bash
   SET_GAUGE_BATCH_JSON="scripts/tasks/migrate-liquidation-helpers/out/<batch>.json" \
   FOUNDRY_PROFILE=core_test forge test \
     --match-contract SetGaugeBatchReplayTest -vvv
   ```
   Test lives at `silo-core/test/foundry/tools/SetGaugeBatchReplay.t.sol`.

## Notes

- Discovery does **not** check bot whitelist on the helpers themselves.
- Empty hook/controller whitelists are skipped in batch generation (warning only).
- Re-runs are idempotent: skip revoke when OLD missing, skip grant when NEW already present.
- Optional `--old-ref <git-ref>` on discover for edge-case OLD resolution.
