---
applyTo: "silo-oracles/contracts/**/*.sol"
---

# Oracle review instructions

This repo contains many oracle implementations under `silo-oracles/contracts/`
(e.g. `chainlinkV3`, `pyth`, `dia`, `supra`, `uniswapV3`, `pendle`, `erc4626`,
`dualOracle`, `custom`, `scaler`, `forwarder`). When a new oracle is added or an
existing one is changed, review it **through the lens of the other oracles**.

When reviewing changes here:

1. **Compare against sibling oracles.** Identify the closest existing oracle(s) and
   check that this change follows the same structure, naming, and safety patterns.
   Point to the sibling oracle when a pattern diverges without good reason.
2. **Required interfaces (mandatory for EVERY oracle).** Confirm the oracle:
   - implements `ISiloOracle` (`silo-core/contracts/interfaces/ISiloOracle.sol`) —
     check `quote()` / `quoteToken()` semantics, return units, and rounding/decimals;
   - inherits the common aggregator base `Aggregator`
     (`silo-oracles/contracts/_common/Aggregator.sol`), which enforces the shared
     `AggregatorV3Interface` shape and the 18-decimals return convention;
   - implements `IVersioned` (`silo-core/contracts/interfaces/IVersioned.sol`,
     `VERSION()`).
   Flag any oracle missing one of these.
3. **Never return a zero price (mandatory for EVERY oracle).** An oracle must
   **revert** instead of returning a price of `0` from `quote()` (and therefore from
   `latestRoundData().answer`). Treat a path that can return `0` as a high-severity
   bug. Confirm there is an explicit revert guard, and that a test asserts this revert.
4. **Price-manipulation surface.** Check staleness / heartbeat checks,
   sequencer-uptime checks where relevant, and sanity bounds on returned prices.
   We do NOT use TWAP pricing — flag any newly introduced TWAP-based logic.
   Compare the rigor of these checks to the strongest sibling oracle.
5. **Regressions.** If a shared library, base contract, or interface in
   `silo-oracles/contracts/_common`, `lib`, or `interfaces` is touched, list which
   other oracles depend on it and whether they could break.
6. **Output normalized to 18 decimals (mandatory for EVERY oracle).** Regardless of
   the base token decimals, the quote token decimals, or the decimals of any
   underlying oracle / aggregator / feed it consumes, the oracle's returned price MUST
   be normalized to **18 decimals**. Trace the decimals math end to end and flag any
   path that can leak source decimals into the output, or that hardcodes an assumption
   (e.g. 8-decimal Chainlink feeds, 6-decimal tokens) without re-scaling to 18.
   Mismatches here are a common and high-severity bug class.

Always prefer aligning with an existing oracle's proven pattern over introducing a
new approach. If you recommend a new approach, justify why the existing pattern is
insufficient.
