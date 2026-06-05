---
applyTo: "**/test/**/*.sol"
---

# Test review instructions

These are Foundry tests (under `*/test/foundry/...`). When reviewing test changes,
or when reviewing contract changes that ship with tests, verify coverage is complete.

Check for:

1. **Case coverage.** For every new or changed code path in the contract under test,
   confirm there is a test. Explicitly list any branch, modifier, or revert path that
   appears uncovered.
2. **Revert assertions.** Each `require` / custom error / access-control guard should
   have a negative test asserting it reverts with the expected error
   (`vm.expectRevert`), not just the happy path.
3. **Boundary & edge cases.** Zero amounts, max values, rounding edges, empty arrays,
   decimals extremes, and first-vs-subsequent interactions.
4. **Fork vs unit.** If the change touches integration with an external protocol or
   oracle, check that there is an appropriate fork test (and that fork tests are not
   accidentally skipped via `_skip_`).
5. **Oracle zero-price revert.** For any oracle, require a test asserting that a
   zero-price scenario **reverts** (oracles must never return a `0` price).
6. **Sibling test patterns.** Mirror the assertion style, fixtures, and mocks used by
   tests for similar contracts (e.g. other oracles) instead of inventing new helpers.

If coverage looks incomplete, comment with the specific missing scenarios rather than
a generic "add more tests".
