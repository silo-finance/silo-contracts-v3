// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationCommon} from "./MaxLiquidationCommon.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxLiquidationDustTest

    cases where when user become insolvent, we do full liquidation because of "dust"
*/
contract MaxLiquidationDustTest is MaxLiquidationCommon {
    using SiloLensLib for ISilo;

    bool private constant _BAD_DEBT = false;

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxLiquidation_dust_sTokens_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 100
    function test_maxLiquidation_dust_sTokens_fuzz(uint8 _collateral) public {
        _maxLiquidation_dust(_collateral, _RECEIVE_STOKENS);
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_dust_tokens_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 100
    function test_maxLiquidation_dust_tokens_fuzz(uint8 _collateral) public {
        _maxLiquidation_dust(_collateral, !_RECEIVE_STOKENS);
    }

    function _maxLiquidation_dust(uint8 _collateral, bool _receiveSToken) internal {
        vm.assume(_collateral == 19 || _collateral == 33);

        _createDebtForBorrower(_collateral);

        _moveTimeUntilInsolvent();

        _assertBorrowerIsNotSolvent(_BAD_DEBT);

        _executeLiquidationAndRunChecks(_receiveSToken);

        _assertBorrowerIsSolvent();
        _ensureBorrowerHasNoDebt();
    }

    function _executeLiquidation(bool _receiveSToken)
        internal
        virtual
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(borrower);

        assertTrue(!sTokenRequired, "sTokenRequired not required");

        emit log_named_decimal_uint("[DustLiquidation] ltv before", silo0.getLtv(borrower), 16);
        emit log_named_uint("[DustLiquidation] debtToRepay", debtToRepay);
        emit log_named_uint("[DustLiquidation] collateralToLiquidate", collateralToLiquidate);

        // to test max, we want to provide higher `_maxDebtToCover` and we expect not higher results
        // also to make sure we can execute with exact `debtToRepay` we will pick exact amount conditionally
        uint256 maxDebtToCover = debtToRepay % 2 == 0 ? type(uint256).max : debtToRepay;

        (withdrawCollateral, repayDebtAssets) = partialLiquidation.liquidationCall(
            address(token0), address(token1), borrower, maxDebtToCover, _receiveSToken
        );

        emit log_named_uint("[DustLiquidation] withdrawCollateral", withdrawCollateral);
        emit log_named_uint("[DustLiquidation] repayDebtAssets", repayDebtAssets);

        assertEq(silo0.getLtv(borrower), 0, "[DustLiquidation] expect full liquidation with dust");
        assertEq(debtToRepay, repayDebtAssets, "[DustLiquidation] debt: maxLiquidation == result");

        _assertEqDiff(
            withdrawCollateral,
            // for self there is no fee, so we get 1 wei more (because this tests are for tiny amounts)
            collateralToLiquidate,
            "[DustLiquidation] collateral: max == result"
        );
    }

    function _withChunks() internal pure virtual override returns (bool) {
        return false;
    }
}
