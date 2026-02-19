// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract TransferReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        MaliciousToken token = MaliciousToken(TestStateLib.token0());
        ISilo silo = TestStateLib.silo0();
        address depositor = makeAddr("Depositor");
        address recipient = makeAddr("Recipient");
        uint256 amount = 100e18;

        TestStateLib.disableReentrancy();

        token.mint(depositor, amount);

        vm.prank(depositor);
        token.approve(address(silo), amount);

        vm.prank(depositor);
        silo.deposit(amount, depositor);

        TestStateLib.enableReentrancy();

        vm.prank(depositor);
        require(silo.transfer(recipient, amount), "transfer failed");
    }

    function verifyReentrancy() external {
        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        require(silo0.transfer(address(0), 1000), "transfer failed");

        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        require(silo1.transfer(address(0), 1000), "transfer failed");
    }

    function methodDescription() external pure returns (string memory description) {
        description = "transfer(address,uint256)";
    }
}
