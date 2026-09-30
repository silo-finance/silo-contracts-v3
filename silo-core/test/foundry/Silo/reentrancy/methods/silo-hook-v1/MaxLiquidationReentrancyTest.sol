// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {TestStateLib} from "../../TestState.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";

contract MaxLiquidationReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "maxLiquidation(address)";
    }

    function _ensureItWillNotRevert() internal view {
        address hookReceiver = TestStateLib.hookReceiver();
        IPartialLiquidation(hookReceiver).maxLiquidation(address(this));
    }
}
