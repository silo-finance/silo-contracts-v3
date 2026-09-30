// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract WithdrawFeesReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        MaliciousToken token0 = MaliciousToken(TestStateLib.token0());
        MaliciousToken token1 = MaliciousToken(TestStateLib.token1());
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");
        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;
        uint256 borrowAmount = 50e18;

        TestStateLib.disableReentrancy();

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        vm.prank(depositor);
        silo0.deposit(depositAmount, depositor);

        vm.startPrank(borrower);
        silo1.deposit(collateralAmount, borrower);
        uint256 shares = silo0.borrow(borrowAmount, borrower, borrower);

        vm.warp(block.timestamp + 10 days);

        silo0.repayShares(shares, borrower);
        vm.stopPrank();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        TestStateLib.enableReentrancy();

        silo0.withdrawFees();
    }

    function verifyReentrancy() external {
        _revertAsExpectedIfNoFees();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "withdrawFees()";
    }

    function _revertAsExpectedIfNoFees() internal {
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo0.withdrawFees();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo1.withdrawFees();
    }
}
