// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract PreviewBorrowSharesReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "previewBorrowShares(uint256)";
    }

    function _ensureItWillNotRevert() internal view {
        TestStateLib.silo0().previewBorrowShares(100_000e18);
        TestStateLib.silo1().previewBorrowShares(100_000e18);
    }
}
