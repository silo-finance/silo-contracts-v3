// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract GetDebtSiloReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        TestStateLib.siloConfig().getDebtSilo(address(0));
    }

    function verifyReentrancy() external view {
        TestStateLib.siloConfig().getDebtSilo(address(0));
    }

    function methodDescription() external pure returns (string memory description) {
        description = "getDebtSilo(address)";
    }
}
