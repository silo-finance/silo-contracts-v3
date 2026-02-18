// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

abstract contract MaxLiquidationCommon is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    bool internal constant _RECEIVE_STOKENS = true;

    ISiloConfig siloConfig;
    address immutable depositor;
    address immutable borrower;

    constructor() {
        depositor = makeAddr("Depositor");
        borrower = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_SILO);
        token1.setOnDemand(true);
    }

    function _createDebtForBorrower(uint128 _collateral) internal {
        vm.assume(_collateral > 0);

        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        collateralConfig = siloConfig.getConfig(address(silo0));
        debtConfig = siloConfig.getConfig(address(silo1));

        uint256 maxLtv = collateralConfig.maxLtv / 1e16; // to avoid overflow on high numbers
        vm.assume(_collateral < type(uint128).max / maxLtv); // to avoid overflow

        uint256 toBorrow = _collateral * maxLtv / 1e2;
        emit log_named_uint("full toBorrow amount", toBorrow);
        vm.assume(toBorrow > 0);

        _depositForBorrow(_collateral, depositor);

        _deposit(_collateral, borrower);
        _borrow(toBorrow, borrower);

        _ensureBorrowerHasDebt();
    }

    function _ensureBorrowerHasDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));
        assertGt(IShareToken(debtShareToken).balanceOf(borrower), 0, "expect borrower has debt balance");
        assertGt(silo0.getLtv(borrower), 0, "expect borrower has some LTV");
    }

    function _ensureBorrowerHasNoDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "expect borrower has NO debt balance");
        assertEq(silo0.getLtv(borrower), 0, "expect borrower has NO LTV");
    }

    function _assertBorrowerIsSolvent() internal view {
        assertTrue(silo1.isSolvent(borrower), "[_assertBorrowerIsSolvent] expect borrower to be solvent");

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrower);
        assertEq(collateralToLiquidate, 0, "[_assertBorrowerIsSolvent] silo0.collateralToLiquidate");
        assertEq(debtToRepay, 0, "[_assertBorrowerIsSolvent] silo0.debtToRepay");

        (collateralToLiquidate, debtToRepay,) = partialLiquidation.maxLiquidation(borrower);
        assertEq(collateralToLiquidate, 0, "[_assertBorrowerIsSolvent] silo1.collateralToLiquidate");
        assertEq(debtToRepay, 0, "[_assertBorrowerIsSolvent] silo1.debtToRepay");
    }

    function _assertLiquidationHookHasNoBalance() internal view {
        assertEq(token0.balanceOf(address(partialLiquidation)), 0, "token0.balanceOf(partialLiquidation)");
        assertEq(token1.balanceOf(address(partialLiquidation)), 0, "token1.balanceOf(partialLiquidation)");

        (address collateralShare, address protectedShare, address debtShare) =
            siloConfig.getShareTokens(address(silo0));
        assertEq(
            IShareToken(collateralShare).balanceOf(address(partialLiquidation)),
            0,
            "collateralShare2.balanceOf(partialLiquidation)"
        );
        assertEq(
            IShareToken(protectedShare).balanceOf(address(partialLiquidation)),
            0,
            "protectedShare2.balanceOf(partialLiquidation)"
        );
        assertEq(
            IShareToken(debtShare).balanceOf(address(partialLiquidation)),
            0,
            "debtShare2.balanceOf(partialLiquidation)"
        );

        (collateralShare, protectedShare, debtShare) = siloConfig.getShareTokens(address(silo1));
        assertEq(
            IShareToken(collateralShare).balanceOf(address(partialLiquidation)),
            0,
            "collateralShare1.balanceOf(partialLiquidation)"
        );
        assertEq(
            IShareToken(protectedShare).balanceOf(address(partialLiquidation)),
            0,
            "protectedShare1.balanceOf(partialLiquidation)"
        );
        assertEq(
            IShareToken(debtShare).balanceOf(address(partialLiquidation)),
            0,
            "debtShare1.balanceOf(partialLiquidation)"
        );
    }

    function _assertBorrowerIsNotSolvent(bool _hasBadDebt) internal {
        uint256 ltv = silo1.getLtv(borrower);
        emit log_named_decimal_uint("[_assertBorrowerIsNotSolvent] LTV", ltv, 16);

        assertFalse(silo1.isSolvent(borrower), "[_assertBorrowerIsNotSolvent] borrower is still solvent");

        if (_hasBadDebt) assertGt(ltv, 1e18, "[_assertBorrowerIsNotSolvent] bad debt LTV");
        else assertLe(ltv, 1e18, "[_assertBorrowerIsNotSolvent] LTV");
    }

    function _assertLTV100() internal {
        uint256 ltv = silo1.getLtv(borrower);
        emit log_named_decimal_uint("[_assertLTV100] LTV", ltv, 16);

        assertFalse(silo1.isSolvent(borrower), "[_assertLTV100] borrower is still solvent");

        assertEq(ltv, 1e18, "[_assertLTV100] LTV");
    }

    function _findLTV100() internal {
        uint256 prevLTV = silo1.getLtv(borrower);

        for (uint256 i = 1; i < 10000; i++) {
            vm.warp(i * 60 * 60 * 24);
            uint256 ltv = silo1.getLtv(borrower);

            emit log_named_decimal_uint("[_assertLTV100] LTV", ltv, 16);
            emit log_named_uint("[_assertLTV100] days", i);

            if (ltv == 1e18) revert("found");

            if (ltv != prevLTV && !silo1.isSolvent(borrower)) {
                emit log_named_decimal_uint("[_assertLTV100] prevLTV was", prevLTV, 16);
                revert("we found middle step between solvent and 100%");
            } else {
                prevLTV = silo1.getLtv(borrower);
            }
        }
    }

    function _moveTimeUntilInsolvent() internal {
        for (uint256 i = 1; i < 10000; i++) {
            emit log_named_decimal_uint("[_moveTimeUntilInsolvent] LTV", silo1.getLtv(borrower), 16);
            emit log_named_uint("[_moveTimeUntilInsolvent] days", i);

            bool isSolvent = silo1.isSolvent(borrower);

            if (!isSolvent) {
                emit log_named_string("[_findWrapForSolvency] user solvent?", isSolvent ? "yes" : "NO");
                return;
            }

            vm.warp(block.timestamp + i * 60 * 60 * 24);
        }
    }

    function _moveTimeUntilBadDebt() internal {
        for (uint256 i = 1; i < 10000; i++) {
            uint256 ltv = silo1.getLtv(borrower);

            emit log_named_decimal_uint("[_assertLTV100] LTV", ltv, 16);
            emit log_named_uint("[_assertLTV100] days", i);

            if (ltv > 1e18) {
                return;
            }

            vm.warp(block.timestamp + i * 60 * 60 * 24);
        }
    }

    function _assertEqDiff(uint256 a, uint256 b, string memory _msg) internal {
        if (a < b) {
            emit log_named_uint("left", a);
            emit log_named_uint("right", b);
            revert(string.concat(_msg, ": error, expected b >= a"));
        }

        // a must be > b, otherwise panic, this is on purpose, we need to know which value can be higher
        // this 2 wei difference is caused by max liquidation underestimation
        assertLe(a - b, 2, string.concat(_msg, " (2wei diff allowed)"));
    }

    function _assertLeDiff(uint256 a, uint256 b, string memory _msg) internal {
        if (a > b) _assertEqDiff(a, b, _msg);
        else assertLe(a, b, _msg);
    }

    function _executeLiquidationAndRunChecks(bool _receiveSToken) internal {
        uint256 siloBalanceBefore0 = token0.balanceOf(address(silo0));
        uint256 siloBalanceBefore1 = token1.balanceOf(address(silo1));

        uint256 liquidatorBalanceBefore0 = token0.balanceOf(address(this));

        (uint256 withdrawCollateral, uint256 repayDebtAssets) = _executeLiquidation(_receiveSToken);

        _assertLiquidationHookHasNoBalance();

        if (_receiveSToken) {
            assertEq(
                siloBalanceBefore0,
                token0.balanceOf(address(silo0)),
                "collateral was NOT moved from silo, because we using sToken"
            );

            assertEq(
                liquidatorBalanceBefore0,
                token0.balanceOf(address(this)),
                "collateral was NOT moved to liquidator, because we using sToken"
            );
        } else {
            assertEq(
                siloBalanceBefore0 - withdrawCollateral,
                token0.balanceOf(address(silo0)),
                "collateral was moved from silo"
            );

            assertEq(
                token0.balanceOf(address(this)),
                liquidatorBalanceBefore0 + withdrawCollateral,
                "collateral was moved to liquidator"
            );
        }

        assertEq(
            siloBalanceBefore1 + repayDebtAssets, token1.balanceOf(address(silo1)), "debt was repay to silo"
        );
    }

    function _calculateChunk(uint256 _maxDebtToCover, uint256 _i) internal view returns (uint256 _chunk) {
        if (_maxDebtToCover == 0) return 0;

        // min amount of assets that will not generate InputZeroShares error
        uint256 minAssets = silo1.previewRepayShares(1);

        if (_i < 2 || _i == 4) {
            // two first iteration and last one (we assume we have max 5 iterations), try to use minimal amount
            if (_maxDebtToCover < minAssets) {
                revert("#1 calculation of maxDebtToCover should never return assets that will generate zero shares");
            }

            return minAssets;
        } else if (_i == 2) {
            // try to liquidate half
            uint256 half = _maxDebtToCover == 1 ? 1 : _maxDebtToCover / 2;
            return half < minAssets ? minAssets : half;
        } else if (_i == 3) {
            // try to liquidate almost everything
            if (_maxDebtToCover < minAssets) {
                revert("#2 calculation of maxDebtToCover should never return assets that will generate zero shares");
            }

            uint256 almostEverything = _maxDebtToCover < minAssets ? minAssets : _maxDebtToCover - minAssets;
            return almostEverything < minAssets ? minAssets : almostEverything;
        } else if (_i == 5) {
            // for iteration 5, we liquidating whatever left
            return _maxDebtToCover;
        } else {
            revert("this should never happen");
        }
    }

    function _liquidationCall(uint256 _maxDebtToCover, bool _receiveSToken)
        internal
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        try partialLiquidation.liquidationCall(
            address(token0), address(token1), borrower, _maxDebtToCover, _receiveSToken
        ) returns (uint256 collateral, uint256 debt) {
            return (collateral, debt);
        } catch (bytes memory data) {
            bytes4 errorType = bytes4(data);

            bytes4 returnZeroAssets = bytes4(keccak256(abi.encodePacked("ReturnZeroAssets()")));
            bytes4 noCollateralToLiquidate = bytes4(keccak256(abi.encodePacked("NoCollateralToLiquidate()")));

            if (errorType == returnZeroAssets) {
                return (0, 0);
            } else if (errorType == noCollateralToLiquidate) {
                return (0, 0);
            }

            revert(string.concat("[_liquidationCall] unexpected error: ", string(data)));
        }
    }

    function _executeLiquidation(bool _receiveSToken)
        internal
        virtual
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets);

    function _withChunks() internal pure virtual returns (bool);
}
