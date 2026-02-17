// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";

import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract InitializeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert"));
        _ensureItWillRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "initialize(address,bytes)";
    }

    function _ensureItWillRevert() internal {
        address hookReceiver = TestStateLib.hookReceiver();
        bytes memory data;
        ISiloConfig config = ISiloConfig(address(this));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        IGaugeHookReceiver(hookReceiver).initialize(config, data);
    }
}
