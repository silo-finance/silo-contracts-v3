// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultsLittleHelper} from "../../_common/VaultsLittleHelper.sol";

/*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mc MaxWithdrawTest
*/
contract MaxWithdrawTest is VaultsLittleHelper {
    address immutable DEPOSITOR;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
    }
    
    /*
    forge test -vv --ffi --mt test_maxWithdraw_zero
    */
    function test_maxWithdraw_zero() public view {
        uint256 maxWithdraw = vault.maxWithdraw(DEPOSITOR);
        assertEq(maxWithdraw, 0, "nothing to withdraw");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_maxWithdraw_deposit_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_maxWithdraw_deposit_fuzz(
        uint112 _assets,
        uint16 _assets2
    ) public {
        vm.assume(_assets > 0);
        vm.assume(_assets2 > 0);

        _deposit(_assets, DEPOSITOR);
        _deposit(_assets2, address(1)); // any

        uint256 maxWithdraw = vault.maxWithdraw(DEPOSITOR);
        assertEq(maxWithdraw, _assets, "max withdraw == _assets if no interest");

        _assertDepositorCanNotWithdrawMore(maxWithdraw);
        _assertMaxWithdrawIsZeroAtTheEnd();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_maxWithdraw_notEnoughLiquidity_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_maxWithdraw_notEnoughLiquidity_fuzz(
        uint128 _collateral,
        uint64 _percentToReduceLiquidity
    ) public {
        vm.assume(_percentToReduceLiquidity <= 1e18);

        uint256 reduced = uint256(_collateral) * _percentToReduceLiquidity / 1e18;
        vm.assume(reduced > 0);

        _reduceLiquidity(_collateral, reduced);

        uint256 maxWithdraw = vault.maxWithdraw(DEPOSITOR);
        assertLt(maxWithdraw, _collateral, "with debt you can not withdraw all");

        _assertDepositorCanNotWithdrawMore(maxWithdraw, 1);
        _assertMaxWithdrawIsZeroAtTheEnd();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_maxWithdraw_whenInterest_
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_maxWithdraw_whenInterest_fuzz(uint128 _collateral) public {
        vm.assume(_collateral > 0);

        vault.deposit(_collateral, DEPOSITOR);

        _createInterest();

        uint256 maxWithdraw = vault.maxWithdraw(DEPOSITOR);
        assertGt(maxWithdraw, _collateral, "expect to earn because we have interest in silo");

        _assertDepositorCanNotWithdrawMore(maxWithdraw, 3);
        _assertMaxWithdrawIsZeroAtTheEnd(1);
    }

    function _assertDepositorCanNotWithdrawMore(uint256 _maxWithdraw) internal {
        _assertDepositorCanNotWithdrawMore(_maxWithdraw, 1);
    }

    function _assertDepositorCanNotWithdrawMore(uint256 _maxWithdraw, uint256 _underestimate) internal {
        assertGt(_underestimate, 0, "_underestimate must be at least 1");

        emit log_named_uint("=== QA [_assertDepositorCanNotWithdrawMore] _maxWithdraw:", _maxWithdraw);
        emit log_named_uint("=== QA [_assertDepositorCanNotWithdrawMore] _underestimate:", _underestimate);

        if (_maxWithdraw > 0) {
            vm.prank(DEPOSITOR);
            vault.withdraw(_maxWithdraw, DEPOSITOR, DEPOSITOR);
        }

        uint256 counterExample = _underestimate;
        emit log_named_uint("=========== [counterexample] testing counterexample for maxWithdraw with", counterExample);

        vm.prank(DEPOSITOR);
        vm.expectRevert();
        vault.withdraw(counterExample, DEPOSITOR, DEPOSITOR);
    }

    function _assertMaxWithdrawIsZeroAtTheEnd() internal {
        _assertMaxWithdrawIsZeroAtTheEnd(0);
    }

    function _assertMaxWithdrawIsZeroAtTheEnd(uint256 _underestimate) internal {
        emit log_named_uint("================= _assertMaxWithdrawIsZeroAtTheEnd ================= +/-", _underestimate);

        uint256 maxWithdraw = vault.maxWithdraw(DEPOSITOR);

        assertLe(
            maxWithdraw,
            _underestimate,
            string.concat("at this point max should return 0 +/-", string(abi.encodePacked(_underestimate)))
        );
    }

    function _reduceLiquidity(uint256 _depositAssets, uint256 _toBorrow) internal {
        _deposit(_depositAssets, DEPOSITOR);

        address borrower = makeAddr("Borrower");

        vm.startPrank(borrower);
        _silo0().deposit(_toBorrow * 10, borrower);
        _silo1().borrow(_toBorrow, borrower, borrower);
        vm.stopPrank();
    }

    function _createInterest() internal {
        vm.prank(DEPOSITOR);
        vault.deposit(type(uint128).max, DEPOSITOR);

        address borrower = makeAddr("Borrower");

        vm.startPrank(borrower);
        _silo0().deposit(type(uint128).max, borrower);
        _silo1().borrow(type(uint64).max, borrower, borrower);

        vm.warp(block.timestamp + 200 days);

        _silo0().accrueInterest();
        _silo1().accrueInterest();

        _silo1().repay(_silo1().maxRepay(borrower), borrower);
        vm.stopPrank();
    }
}
