// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract UpdateHooksReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));

        TestStateLib.silo0().updateHooks();
        TestStateLib.silo1().updateHooks();
    }

    function verifyReentrancy() external {
        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo0.updateHooks();

        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo1.updateHooks();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "updateHooks()";
    }
}
