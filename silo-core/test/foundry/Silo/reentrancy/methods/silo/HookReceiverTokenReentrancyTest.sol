// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract HookReceiverTokenReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "hookReceiver()";
    }

    function _ensureItWillNotRevert() internal view {
        IShareToken(address(TestStateLib.silo0())).hookReceiver();
        IShareToken(address(TestStateLib.silo1())).hookReceiver();
    }
}
