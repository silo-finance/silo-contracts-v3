// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";

import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract RemoveGaugeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert (permissions)"));
        _ensureItWillRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "removeGauge(address)";
    }

    function _ensureItWillRevert() internal {
        address hookReceiver = TestStateLib.hookReceiver();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));

        IGaugeHookReceiver(hookReceiver).removeGauge(IShareToken(address(this)));
    }
}
