// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract BeforeActionReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert (method disabled)"));
        _ensureItWillRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "beforeAction(address,uint256,bytes)";
    }

    function _ensureItWillRevert() internal {
        address hookReceiver = TestStateLib.hookReceiver();

        vm.expectRevert(IHookReceiver.OnlySilo.selector);
        IGaugeHookReceiver(hookReceiver).beforeAction(address(this), 0, "");
    }
}
