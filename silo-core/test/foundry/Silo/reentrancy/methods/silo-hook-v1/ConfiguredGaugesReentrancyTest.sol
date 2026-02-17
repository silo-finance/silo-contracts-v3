// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract ConfiguredGaugesReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "configuredGauges(address)";
    }

    function _ensureItWillNotRevert() internal view {
        address hookReceiver = TestStateLib.hookReceiver();
        IGaugeHookReceiver(hookReceiver).configuredGauges(IShareToken(address(this)));
    }
}
