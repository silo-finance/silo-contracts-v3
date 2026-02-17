// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC5267} from "openzeppelin5/interfaces/IERC5267.sol";

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract Eip712DomainReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "eip712Domain()";
    }

    function _ensureItWillNotRevert() internal view {
        IERC5267(address(TestStateLib.silo0())).eip712Domain();
        IERC5267(address(TestStateLib.silo1())).eip712Domain();
    }
}
