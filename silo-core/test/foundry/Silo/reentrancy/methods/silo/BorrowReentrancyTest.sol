// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract BorrowReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        MaliciousToken token1 = MaliciousToken(TestStateLib.token1());
        MaliciousToken token0 = MaliciousToken(TestStateLib.token0());
        ISilo silo1 = TestStateLib.silo1();
        ISilo silo0 = TestStateLib.silo0();
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");
        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;

        TestStateLib.disableReentrancy();

        token0.mint(depositor, depositAmount);
        token1.mint(borrower, collateralAmount);

        vm.prank(depositor);
        token0.approve(address(silo0), depositAmount);

        vm.prank(depositor);
        silo0.deposit(depositAmount, depositor);

        vm.prank(borrower);
        token1.approve(address(silo1), collateralAmount);

        vm.prank(borrower);
        silo1.deposit(collateralAmount, borrower);

        TestStateLib.enableReentrancy();

        uint256 borrowAmount = silo0.maxBorrow(borrower);

        if (borrowAmount == 0) {
            console2.log("[BorrowReentrancyTest] borrow amount is 0");
            revert("[BorrowReentrancyTest] borrow amount is 0");
        }

        vm.prank(borrower);
        silo0.borrow(borrowAmount, borrower, borrower);
    }

    function verifyReentrancy() external {
        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo1.borrow(1000, address(0), address(0));

        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo0.borrow(1000, address(0), address(0));
    }

    function methodDescription() external pure returns (string memory description) {
        description = "borrow(uint256,address,address)";
    }
}
