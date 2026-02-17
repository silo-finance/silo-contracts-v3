// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract SetReceiverApprovalReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));

        ISiloConfig config = TestStateLib.siloConfig();
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        address borrower = makeAddr("Borrower");
        address receiver = makeAddr("Receiver");

        (,, address debtToken) = config.getShareTokens(address(silo0));

        vm.prank(receiver);
        ShareDebtToken(debtToken).setReceiveApproval(borrower, 0);

        (,, debtToken) = config.getShareTokens(address(silo1));

        vm.prank(receiver);
        ShareDebtToken(debtToken).setReceiveApproval(borrower, 0);
    }

    function verifyReentrancy() external {
        ISiloConfig config = TestStateLib.siloConfig();
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        (,, address debtToken) = config.getShareTokens(address(silo0));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        ShareDebtToken(debtToken).setReceiveApproval(address(0), 0);

        (,, debtToken) = config.getShareTokens(address(silo1));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        ShareDebtToken(debtToken).setReceiveApproval(address(0), 0);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "setReceiveApproval(address,uint256)";
    }
}
