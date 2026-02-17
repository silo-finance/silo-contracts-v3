// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationBadDebtTest} from "./MaxLiquidation_badDebt.i.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxLiquidationBadDebtWithChunksTest

    same as MaxLiquidationBadDebtTest but with chunks
*/
contract MaxLiquidationBadDebtWithChunksTest is MaxLiquidationBadDebtTest {
    using SiloLensLib for ISilo;

    bool private constant _BAD_DEBT = true;

    function _maxLiquidation_partial(uint128 _collateral, bool _receiveSToken) internal override {
        _createDebtForBorrower(_collateral);

        vm.warp(block.timestamp + 50 days); // initial time movement to speed up _moveTimeUntilInsolvent

        // for same asset interest increasing slower, because borrower is also depositor, also LT is higher
        _moveTimeUntilBadDebt();

        _assertBorrowerIsNotSolvent(_BAD_DEBT);

        _executeLiquidationAndRunChecks(_receiveSToken);

        // with bad debt for 2 tokens we can not assert anything after liquidations with chunks
        // it is possible to leave position with 0 collateral and 2 debt
        // because for bad debt there is no dust protection
    }

    function _executeLiquidation(bool _receiveSToken)
        internal
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        (uint256 totalCollateralToLiquidate, uint256 totalDebtToCover,) =
            partialLiquidation.maxLiquidation(borrower);

        emit log_named_decimal_uint("[BadDebtWithChunks] ltv before", silo0.getLtv(borrower), 16);
        emit log_named_uint("[BadDebtWithChunks] totalCollateralToLiquidate", totalCollateralToLiquidate);
        emit log_named_uint("[BadDebtWithChunks] totalDebtToCover", totalDebtToCover);

        for (uint256 i; i < 5; i++) {
            emit log_named_uint("[BadDebtWithChunks] case ------------------------", i);
            emit log_named_decimal_uint("ltv", silo0.getLtv(borrower), 16);

            if (silo0.getLtv(borrower) <= 1e18) break; // not bad debt anymore

            {
                // too deep
                bool isSolvent = silo0.isSolvent(borrower);
                emit log_named_string("isSolvent", isSolvent ? "YES" : "NO");

                if (isSolvent) break;
            }

            emit log_named_uint(
                "collateralBalanceOfUnderlying", siloLens.collateralBalanceOfUnderlying(silo1, borrower)
            );
            emit log_named_uint("debtBalanceOfUnderlying", siloLens.debtBalanceOfUnderlying(silo1, borrower));
            emit log_named_uint("total(collateral).assets", silo1.getTotalAssetsStorage(ISilo.AssetType.Collateral));
            emit log_named_uint("getCollateralAssets()", silo1.getCollateralAssets());

            uint256 collateralToLiquidate;
            uint256 maxDebtToCover;
            (collateralToLiquidate, maxDebtToCover,) = partialLiquidation.maxLiquidation(borrower);

            emit log_named_uint("[BadDebtWithChunks] collateralToLiquidate", collateralToLiquidate);
            emit log_named_uint("[BadDebtWithChunks] maxDebtToCover", maxDebtToCover);

            if (collateralToLiquidate == 0) {
                assertGt(silo0.getLtv(borrower), 1e18, "when no collateral we expect bad debt");
                continue;
            }

            uint256 testDebtToCover = _calculateChunk(maxDebtToCover, i);
            emit log_named_uint("[BadDebtWithChunks] testDebtToCover", testDebtToCover);

            (uint256 partialCollateral, uint256 partialDebt) =
                _liquidationCall(testDebtToCover, _receiveSToken);

            emit log_named_uint("[BadDebtWithChunks] partialCollateral", partialCollateral);
            emit log_named_uint("[BadDebtWithChunks] partialDebt", partialDebt);

            _assertLeDiff(partialCollateral, collateralToLiquidate, "partialCollateral");

            withdrawCollateral += partialCollateral;
            repayDebtAssets += partialDebt;
        }

        emit log_named_decimal_uint("ltv", silo0.getLtv(borrower), 16);

        // sum of chunk liquidation can be smaller than one max/total, because with chunks we can get to the point
        // where user became solvent and the margin we have for max liquidation will not be used
        assertLe(repayDebtAssets, totalDebtToCover, "chunks(debt) can not be bigger than total/max");

        /*
        for not bad debt, we were checking this:

        _assertLeDiff(
            withdrawCollateral,
            totalCollateralToLiquidate,
            "chunks(collateral) can not be bigger than total/max"
        );

        however with bad debt and chunk liquidation, each liquidation leave borrower with higher debt, means
        there will be higher interest (so same share is worth more), and that means next liquidation will give us
        more collateral, so sum of partial collateral can be higher than doing just one, so this assertion will not work
        */
    }

    function _withChunks() internal pure override returns (bool) {
        return true;
    }
}
