// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {Ownable1and2Steps} from "common/access/Ownable1and2Steps.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract TransferOwnership1StepReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert"));
        _ensureItWillRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "transferOwnership1Step(address)";
    }

    function _ensureItWillRevert() internal {
        address hookReceiver = TestStateLib.hookReceiver();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));

        Ownable1and2Steps(hookReceiver).transferOwnership1Step(address(this));
    }
}
