// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {TestStateLib} from "../../TestState.sol";

contract AllowanceReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "allowance(address,address)";
    }

    function _ensureItWillNotRevert() internal {
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        address anyAddr1 = makeAddr("Any address 1");
        address anyAddr2 = makeAddr("Any address 2");

        silo0.allowance(anyAddr1, anyAddr2);
        silo1.allowance(anyAddr1, anyAddr2);
    }
}
