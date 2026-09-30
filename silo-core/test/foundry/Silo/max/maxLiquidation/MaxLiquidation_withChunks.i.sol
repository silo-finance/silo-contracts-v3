// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationTest} from "./MaxLiquidation.i.sol";

/*
    forge test -vv --ffi --mc MaxLiquidationWithChunksTest

    this tests are MaxLiquidationTest cases, difference is, we splitting max liquidation in chunks
*/
contract MaxLiquidationWithChunksTest is MaxLiquidationTest {
    using SiloLensLib for ISilo;

    function _executeLiquidation(bool _receiveSToken)
        internal
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        (uint256 totalCollateralToLiquidate, uint256 totalDebtToCover,) =
            // forge-lint: disable-next-line(unused-return)
            partialLiquidation.maxLiquidation(BORROWER);

        for (uint256 i; i < 5; i++) {
            // forge-lint: disable-next-line(reentrancy-events)
            emit log_named_uint("[MaxLiquidationWithChunks] case ------------------------", i);

            // forge-lint: disable-next-line(calls-loop, reentrancy-events)
            emit log_named_string("isSolvent", silo0.isSolvent(BORROWER) ? "YES" : "NO");
            // forge-lint: disable-next-line(reentrancy-events)
            emit log_named_decimal_uint("[MaxLiquidationWithChunks] ltv before", silo0.getLtv(BORROWER), 16);

            // forge-lint: disable-next-line(calls-loop, unused-return)
            (uint256 collateralToLiquidate, uint256 maxDebtToCover,) = partialLiquidation.maxLiquidation(BORROWER);

            // forge-lint: disable-next-line(calls-loop)
            bool isSolvent = silo0.isSolvent(BORROWER);

            // this conditions caught bug
            // forge-lint: disable-next-line(require-revert-in-loop)
            if (isSolvent && maxDebtToCover != 0) revert("if we solvent there should be no liquidation");
            // forge-lint: disable-next-line(require-revert-in-loop)
            if (!isSolvent && maxDebtToCover == 0) revert("if we NOT solvent there should be a liquidation");

            if (isSolvent) break;

            uint256 testDebtToCover = _calculateChunk(maxDebtToCover, i);

            (uint256 partialCollateral, uint256 partialDebt) =
                _liquidationCall(testDebtToCover, _receiveSToken);

            withdrawCollateral += partialCollateral;
            repayDebtAssets += partialDebt;

            _assertLeDiff(partialCollateral, collateralToLiquidate, "partialCollateral");
        }

        // sum of chunk liquidation can be smaller than one max/total, because with chunks we can get to the point
        // where user became solvent and the margin we have for max liquidation will not be used
        assertLe(repayDebtAssets, totalDebtToCover, "chunks(debt) can not be bigger than total/max");

        _assertLeDiff(
            withdrawCollateral, totalCollateralToLiquidate, "chunks(collateral) can not be bigger than total/max"
        );
    }

    function _withChunks() internal pure override returns (bool) {
        return true;
    }
}
