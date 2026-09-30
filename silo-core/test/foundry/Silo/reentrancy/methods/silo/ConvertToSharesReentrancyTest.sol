// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Silo} from "silo-core/contracts/Silo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract ConvertToSharesReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "convertToShares(uint256)";
    }

    function _ensureItWillNotRevert() internal view {
        Silo(payable(address(TestStateLib.silo0()))).convertToShares(100e18);
        Silo(payable(address(TestStateLib.silo1()))).convertToShares(100e18);
    }
}
