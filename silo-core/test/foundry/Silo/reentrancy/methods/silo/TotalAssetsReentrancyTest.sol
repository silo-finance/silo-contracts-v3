// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Silo} from "silo-core/contracts/Silo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract TotalAssetsReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "totalAssets()";
    }

    function _ensureItWillNotRevert() internal view {
        // forge-lint: disable-next-line(unused-return)
        Silo(payable(address(TestStateLib.silo0()))).totalAssets();
        // forge-lint: disable-next-line(unused-return)
        Silo(payable(address(TestStateLib.silo1()))).totalAssets();
    }
}
