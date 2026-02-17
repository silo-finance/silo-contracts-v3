// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationLTV100FullTest} from "./MaxLiquidation_LTV100Full.i.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxLiquidationLTV100FullWithChunksTest

    this tests are MaxLiquidationLTV100FullWith cases, difference is, we splitting max liquidation in chunks
*/
contract MaxLiquidationLTV100FullWithChunksTest is MaxLiquidationLTV100FullTest {
    using SiloLensLib for ISilo;

    function _executeLiquidation(bool _receiveSToken)
        internal
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        (uint256 totalCollateralToLiquidate, uint256 totalDebtToCover,) =
            partialLiquidation.maxLiquidation(borrower);

        emit log_named_decimal_uint("[LTV100FullWithChunks] ltv before", silo0.getLtv(borrower), 16);

        for (uint256 i; i < 6; i++) {
            emit log_named_uint("[LTV100FullWithChunks] case ------------------------", i);

            emit log_named_string("isSolvent", silo0.isSolvent(borrower) ? "YES" : "NO");

            (uint256 collateralToLiquidate, uint256 maxDebtToCover,) = partialLiquidation.maxLiquidation(borrower);
            emit log_named_uint("[LTV100FullWithChunks] collateralToLiquidate", collateralToLiquidate);
            if (maxDebtToCover == 0) continue;

            (,,, bool fullLiquidation) = siloLens.maxLiquidation(silo1, partialLiquidation, borrower);
            assertTrue(fullLiquidation, "[LTV100FullWithChunks] fullLiquidation flag is UP when LTV is 100%");

            if (collateralToLiquidate == 0) {
                assertGe(silo0.getLtv(borrower), 1e18, "if we don't have collateral we expect bad debt");
                continue;
            }

            {
                // too deep
                bool isSolvent = silo0.isSolvent(borrower);

                if (isSolvent && maxDebtToCover != 0) revert("if we solvent there should be no liquidation");
                if (!isSolvent && maxDebtToCover == 0) revert("if we NOT solvent there should be a liquidation");

                if (isSolvent) break;
            }

            uint256 testDebtToCover = _calculateChunk(maxDebtToCover, i);
            emit log_named_uint("[LTV100FullWithChunks] testDebtToCover", testDebtToCover);

            (uint256 partialCollateral, uint256 partialDebt) =
                _liquidationCall(testDebtToCover, _receiveSToken);

            _assertLeDiff(partialCollateral, collateralToLiquidate, "partialCollateral");

            withdrawCollateral += partialCollateral;
            repayDebtAssets += partialDebt;
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
