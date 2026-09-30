// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Permit} from "openzeppelin5/token/ERC20/extensions/IERC20Permit.sol";

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract NoncesReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "nonces(address)";
    }

    function _ensureItWillNotRevert() internal view {
        IERC20Permit(address(TestStateLib.silo0())).nonces(address(1));
        IERC20Permit(address(TestStateLib.silo1())).nonces(address(1));
    }
}
