// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable2Step} from "openzeppelin5/access/Ownable2Step.sol";

import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract PendingOwnerReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "pendingOwner()";
    }

    function _ensureItWillNotRevert() internal view {
        Ownable2Step(TestStateLib.hookReceiver()).pendingOwner();
    }
}
