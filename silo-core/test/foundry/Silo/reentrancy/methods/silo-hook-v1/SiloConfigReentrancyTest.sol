// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloHookV1} from "silo-core/contracts/hooks/SiloHookV1.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract SiloConfigReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "siloConfig()";
    }

    function _ensureItWillNotRevert() internal view {
        address hookReceiver = TestStateLib.hookReceiver();
        SiloHookV1(hookReceiver).siloConfig();
    }
}
