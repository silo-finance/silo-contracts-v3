// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {MaxWithdrawCommon} from "./MaxWithdrawCommon.sol";

/*
    forge test -vv --ffi --mc MaxWithdrawTest
*/
contract MaxWithdrawTest is MaxWithdrawCommon {
    using SiloLensLib for ISilo;

    function setUp() public {
        _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_maxWithdraw_zero
    */
    function test_maxWithdraw_zero() public view {
        uint256 maxWithdraw = silo1.maxWithdraw(borrower);
        assertEq(maxWithdraw, 0, "nothing to withdraw");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_deposit_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxWithdraw_deposit_fuzz(uint112 _assets, uint16 _assets2) public {
        vm.assume(_assets > 0);
        vm.assume(_assets2 > 0);

        _deposit(_assets, borrower);
        _deposit(_assets2, address(1)); // any

        uint256 maxWithdraw = silo0.maxWithdraw(borrower);
        assertEq(maxWithdraw, _assets - 1, "max withdraw == _assets if no interest (-1 for underestimation)");

        _assertBorrowerCanNotWithdrawMore(maxWithdraw, 2);
        _assertMaxWithdrawIsZeroAtTheEnd();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_withDebt_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxWithdraw_withDebt_fuzz(uint128 _collateral, uint128 _toBorrow) public {
        _createDebtOnSilo1(_collateral, _toBorrow);

        ISilo collateralSilo = silo0;

        uint256 maxWithdraw = collateralSilo.maxWithdraw(borrower);
        assertLt(maxWithdraw, _collateral, "with debt you can not withdraw all");

        emit log_named_decimal_uint("LTV", collateralSilo.getLtv(borrower), 16);

        _assertBorrowerCanNotWithdrawMore(maxWithdraw, 4);
        _assertMaxWithdrawIsZeroAtTheEnd(1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_withDebtAndNotEnoughLiquidity_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxWithdraw_withDebtAndNotEnoughLiquidity_fuzz(
        uint128 _collateral,
        uint128 _toBorrow,
        uint64 _percentToBorrowOnSilo0
    ) public {
        // (uint128 _collateral, uint128 _toBorrow, uint64 _percentToBorrowOnSilo0) = (27114386650, 1, 18440395);

        vm.assume(_percentToBorrowOnSilo0 <= 1e18);

        _createDebtOnSilo1(_collateral, _toBorrow);

        ISilo collateralSilo = silo0;

        uint256 borrowOnSilo0 = collateralSilo.getCollateralAssets() * _percentToBorrowOnSilo0 / 1e18;

        emit log_named_decimal_uint("_percentToBorrowOnSilo0", _percentToBorrowOnSilo0, 18);
        emit log_named_decimal_uint("borrowOnSilo0", borrowOnSilo0, 18);

        if (borrowOnSilo0 > 0) {
            address any = makeAddr("yet another user");
            _depositForBorrow(borrowOnSilo0 * 2, any);
            vm.prank(any);
            collateralSilo.borrow(borrowOnSilo0, any, any);
            emit log_named_decimal_uint("LTV any", silo1.getLtv(any), 16);
        }

        uint256 maxWithdraw = collateralSilo.maxWithdraw(borrower);
        assertLt(maxWithdraw, _collateral, "with debt you can not withdraw all");

        emit log_named_decimal_uint("LTV", silo1.getLtv(borrower), 16);

        _assertBorrowerCanNotWithdrawMore(maxWithdraw, 4);
        _assertMaxWithdrawIsZeroAtTheEnd(1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_whenInterest_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxWithdraw_whenInterest_fuzz(uint128 _collateral, uint128 _toBorrow) public {
        _createDebtOnSilo1(_collateral, _toBorrow);

        vm.warp(block.timestamp + 100 days);

        ISilo collateralSilo = silo0;
        uint256 maxWithdraw = collateralSilo.maxWithdraw(borrower);
        assertLt(maxWithdraw, _collateral, "with debt you can not withdraw all");

        emit log_named_decimal_uint("LTV before withdraw", silo1.getLtv(borrower), 16);
        emit log_named_uint("maxWithdraw", maxWithdraw);

        _assertBorrowerCanNotWithdrawMore(maxWithdraw, 4);
        _assertMaxWithdrawIsZeroAtTheEnd(1);
    }

    /*
    forge test -vv --ffi --mt test_maxWithdraw_bothSilosWithInterest_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxWithdraw_bothSilosWithInterest_fuzz(uint128 _collateral, uint128 _toBorrow) public {
        // (uint128 _collateral, uint128 _toBorrow) = (13637, 380);

        _createDebtOnSilo0(_collateral, _toBorrow);
        _createDebtOnSilo1(_collateral, _toBorrow);

        vm.warp(block.timestamp + 100 days);

        ISilo collateralSilo = silo0;
        uint256 maxWithdraw = collateralSilo.maxWithdraw(borrower);
        assertLt(maxWithdraw, _collateral, "with debt you can not withdraw all");

        emit log_named_decimal_uint("LTV before withdraw", silo1.getLtv(borrower), 16);
        emit log_named_uint("maxWithdraw", maxWithdraw);

        _assertBorrowerCanNotWithdrawMore(maxWithdraw, 4);
        _assertMaxWithdrawIsZeroAtTheEnd(1);
    }

    function _assertBorrowerHasNothingToWithdraw() internal view {
        (, address collateralShareToken,) = silo0.config().getShareTokens(address(silo0));

        assertEq(silo0.maxWithdraw(borrower), 0, "expect maxWithdraw to be 0");
        assertEq(IShareToken(collateralShareToken).balanceOf(borrower), 0, "expect share balance to be 0");
    }

    function _assertBorrowerCanNotWithdrawMore(uint256 _maxWithdraw) internal {
        _assertBorrowerCanNotWithdrawMore(_maxWithdraw, 1);
    }

    function _assertBorrowerCanNotWithdrawMore(uint256 _maxWithdraw, uint256 _underestimate) internal {
        assertGt(_underestimate, 0, "_underestimate must be at least 1");

        emit log_named_uint("=== QA [_assertBorrowerCanNotWithdrawMore] _maxWithdraw:", _maxWithdraw);
        emit log_named_uint("=== QA [_assertBorrowerCanNotWithdrawMore] _underestimate:", _underestimate);

        ISilo collateralSilo = silo0;

        if (_maxWithdraw > 0) {
            vm.prank(borrower);
            collateralSilo.withdraw(_maxWithdraw, borrower, borrower);
            emit log_named_decimal_uint("[_assertBorrowerCanNotWithdrawMore] LTV", silo1.getLtv(borrower), 16);
        }

        bool isSolvent = collateralSilo.isSolvent(borrower);

        if (!isSolvent) {
            assertEq(_maxWithdraw, 0, "if user is insolvent, MAX should be always 0");
        }

        uint256 counterExample = isSolvent ? _underestimate : 1;
        emit log_named_uint(
            "=========== [counterexample] testing counterexample for maxWithdraw with", counterExample
        );

        vm.prank(borrower);
        vm.expectRevert();
        collateralSilo.withdraw(counterExample, borrower, borrower);
    }

    function _assertMaxWithdrawIsZeroAtTheEnd() internal {
        _assertMaxWithdrawIsZeroAtTheEnd(0);
    }

    function _assertMaxWithdrawIsZeroAtTheEnd(uint256 _underestimate) internal {
        emit log_named_uint(
            "================= _assertMaxWithdrawIsZeroAtTheEnd ================= +/-", _underestimate
        );

        ISilo collateralSilo = silo0;
        uint256 maxWithdraw = collateralSilo.maxWithdraw(borrower);

        assertLe(
            maxWithdraw,
            _underestimate,
            string.concat("at this point max should return 0 +/-", string(abi.encodePacked(_underestimate)))
        );
    }
}
