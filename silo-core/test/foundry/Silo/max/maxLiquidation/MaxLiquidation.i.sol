// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationCommon} from "./MaxLiquidationCommon.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxLiquidationTest

    this tests are for "normal" case,
    where user became insolvent and we can partially liquidate
*/
contract MaxLiquidationTest is MaxLiquidationCommon {
    using SiloLensLib for ISilo;

    bool private constant _BAD_DEBT = false;

    /*
    forge test -vv --ffi --mt test_maxLiquidation_noDebt
    */
    function test_maxLiquidation_noDebt() public {
        _assertBorrowerIsSolvent();

        _depositForBorrow(11e18, borrower);
        _deposit(11e18, borrower);

        _assertBorrowerIsSolvent();
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_partial_sTokens_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_maxLiquidation_partial_sTokens_fuzz(uint128 _collateral) public {
        _maxLiquidation_partial(_collateral, _RECEIVE_STOKENS);
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_partial_tokens_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_maxLiquidation_partial_tokens_fuzz(uint128 _collateral) public {
        _maxLiquidation_partial(_collateral, !_RECEIVE_STOKENS);
    }

    function _maxLiquidation_partial(uint128 _collateral, bool _receiveSToken) internal virtual {
        vm.assume(_collateral != 19); // dust case
        vm.assume(_collateral != 33); // dust
        vm.assume(_collateral >= 7); // LTV100 cases

        _createDebtForBorrower(_collateral);

        // for same asset interest increasing slower, because borrower is also depositor, also LT is higher
        _moveTimeUntilInsolvent();

        _assertBorrowerIsNotSolvent(_BAD_DEBT);

        (,,, bool fullLiquidation) = siloLens.maxLiquidation(silo1, partialLiquidation, borrower);

        _executeLiquidationAndRunChecks(_receiveSToken);

        _assertBorrowerIsSolvent();

        // 12 case allow for full liquidation and when done with chunks it stays at LTV 100 till the end
        if (_collateral == 12) {
            _ensureBorrowerHasNoDebt();
        } else {
            assertFalse(fullLiquidation, "[MaxLiquidation] fullLiquidation flag is DOWN on partial liquidation");
            _ensureBorrowerHasDebt();
        }
    }

    function _executeLiquidation(bool _receiveSToken)
        internal
        virtual
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        // to test max, we want to provide higher `_maxDebtToCover` and we expect not higher results
        uint256 maxDebtToCover = type(uint256).max;

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrower);

        emit log_named_decimal_uint("[MaxLiquidation] collateralToLiquidate", collateralToLiquidate, 18);
        emit log_named_decimal_uint("[MaxLiquidation] debtToRepay", debtToRepay, 16);
        emit log_named_decimal_uint("[MaxLiquidation] ltv before", silo0.getLtv(borrower), 16);

        (withdrawCollateral, repayDebtAssets) = partialLiquidation.liquidationCall(
            address(token0), address(token1), borrower, maxDebtToCover, _receiveSToken
        );

        emit log_named_decimal_uint("[MaxLiquidation] ltv after", silo0.getLtv(borrower), 16);

        assertEq(debtToRepay, repayDebtAssets, "[MaxLiquidation] debt: maxLiquidation == result");
        _assertEqDiff(withdrawCollateral, collateralToLiquidate, "[MaxLiquidation] collateral: max == result");
    }

    function _withChunks() internal pure virtual override returns (bool) {
        return false;
    }
}
