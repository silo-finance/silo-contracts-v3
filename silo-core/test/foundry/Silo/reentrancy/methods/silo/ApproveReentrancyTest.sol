// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract ApproveReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertReentrancy();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "approve(address,uint256)";
    }

    function _ensureItWillNotRevert() internal {
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        address anyAddr = makeAddr("Any address");

        silo0.approve(anyAddr, 1e18);
        silo1.approve(anyAddr, 1e18);
    }

    function _ensureItWillRevertReentrancy() internal {
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo0.approve(address(0), 1e18);

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        silo1.approve(address(0), 1e18);
    }
}
