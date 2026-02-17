// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationCommon} from "./MaxLiquidationCommon.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxLiquidationLTV100FullTest

    cases where we go from solvent to 100% and we must do full liquidation
*/
contract MaxLiquidationLTV100FullTest is MaxLiquidationCommon {
    using SiloLensLib for ISilo;

    /*
    forge test -vv --ffi --mt test_maxLiquidation_LTV100_full_sToken_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 100
    function test_maxLiquidation_LTV100_full_sToken_fuzz(uint8 _collateral) public {
        _maxLiquidation_LTV100_full(_collateral, _RECEIVE_STOKENS);
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_LTV100_full_token_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 100
    function test_maxLiquidation_LTV100_full_token_fuzz(uint8 _collateral) public {
        _maxLiquidation_LTV100_full(_collateral, !_RECEIVE_STOKENS);
    }

    function _maxLiquidation_LTV100_full(uint8 _collateral, bool _receiveSToken) internal {
        vm.assume(_collateral < 7);

        _createDebtForBorrower(_collateral);

        // this case (1) never happen because is is not possible to create debt for 1 collateral
        if (_collateral == 1) _findLTV100();
        else if (_collateral == 2) vm.warp(3615 days);
        else if (_collateral == 3) vm.warp(66 days);
        else if (_collateral == 4) vm.warp(45 days);
        else if (_collateral == 5) vm.warp(95 days);
        else if (_collateral == 6) vm.warp(66 days);
        else revert("should not happen, because of vm.assume");

        _assertLTV100();

        _executeLiquidationAndRunChecks(_receiveSToken);
    }

    function _executeLiquidation(bool _receiveSToken)
        internal
        virtual
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        // to test max, we want to provide higher `_maxDebtToCover` and we expect not higher results
        uint256 maxDebtToCover = type(uint256).max;

        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(borrower);

        (,,, bool fullLiquidation) = siloLens.maxLiquidation(silo1, partialLiquidation, borrower);
        assertTrue(fullLiquidation, "[100FULL] fullLiquidation flag is UP when LTV is 100%");

        emit log_named_uint("[100FULL] collateralToLiquidate", collateralToLiquidate);
        uint256 ltv = silo0.getLtv(borrower);
        emit log_named_decimal_uint("[100FULL] ltv before", ltv, 16);

        if (collateralToLiquidate == 0) {
            assertGe(ltv, 1e18, "[100FULL] if we don't have collateral we expect bad debt");
            return (0, 0);
        }

        assertTrue(!sTokenRequired, "sTokenRequired NOT required");

        (withdrawCollateral, repayDebtAssets) = partialLiquidation.liquidationCall(
            address(token0), address(token1), borrower, maxDebtToCover, _receiveSToken
        );

        emit log_named_decimal_uint("[100FULL] ltv after", silo0.getLtv(borrower), 16);
        emit log_named_decimal_uint("[100FULL] collateralToLiquidate", collateralToLiquidate, 18);

        assertEq(debtToRepay, repayDebtAssets, "[100FULL] debt: maxLiquidation == result");

        _assertEqDiff(withdrawCollateral, collateralToLiquidate, "[100FULL] collateral: max == result");
    }

    function _withChunks() internal pure virtual override returns (bool) {
        return false;
    }
}
