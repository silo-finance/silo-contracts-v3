// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";
import {TestStateLib} from "../../TestState.sol";

contract TransferFromReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        MaliciousToken token0 = MaliciousToken(TestStateLib.token0());
        MaliciousToken token1 = MaliciousToken(TestStateLib.token1());
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");
        address receiver = makeAddr("Receiver");
        address spender = makeAddr("Spender");
        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;
        uint256 borrowAmount = 50e18;

        TestStateLib.disableReentrancy();

        token0.mint(depositor, depositAmount);
        token1.mint(borrower, collateralAmount);
        token1.mint(receiver, collateralAmount);

        vm.prank(depositor);
        token0.approve(address(silo0), depositAmount);

        vm.prank(depositor);
        silo0.deposit(depositAmount, depositor);

        vm.prank(borrower);
        token1.approve(address(silo1), collateralAmount);

        vm.prank(borrower);
        silo1.deposit(collateralAmount, borrower);

        vm.prank(borrower);
        silo0.borrow(borrowAmount, borrower, borrower);

        (,, address debtToken) = TestStateLib.siloConfig().getShareTokens(address(silo0));

        vm.prank(borrower);
        ShareDebtToken(debtToken).approve(spender, borrowAmount);

        vm.prank(receiver);
        ShareDebtToken(debtToken).setReceiveApproval(borrower, borrowAmount);

        vm.prank(receiver);
        token1.approve(address(silo1), collateralAmount);

        vm.prank(receiver);
        silo1.deposit(collateralAmount, receiver);

        TestStateLib.enableReentrancy();

        vm.prank(spender);
        require(ShareDebtToken(debtToken).transferFrom(borrower, receiver, borrowAmount), "transfer failed");
    }

    function verifyReentrancy() external {
        ISiloConfig config = TestStateLib.siloConfig();
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        (,, address debtToken) = config.getShareTokens(address(silo0));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        require(ShareDebtToken(debtToken).transferFrom(address(0), address(0), 0), "transfer failed");

        (,, debtToken) = config.getShareTokens(address(silo1));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        require(ShareDebtToken(debtToken).transferFrom(address(0), address(0), 0), "transfer failed");
    }

    function methodDescription() external pure returns (string memory description) {
        description = "transferFrom(address,address,uint256)";
    }
}
