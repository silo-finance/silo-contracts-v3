// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";

import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract OwnerReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "owner()";
    }

    function _ensureItWillNotRevert() internal view {
        Ownable(TestStateLib.hookReceiver()).owner();
    }
}
