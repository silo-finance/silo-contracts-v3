// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract GetFeesWithAssetReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "getFeesWithAsset(address)";
    }

    function _ensureItWillNotRevert() internal view {
        address silo0 = address(TestStateLib.silo0());
        address silo1 = address(TestStateLib.silo1());

        TestStateLib.siloConfig().getFeesWithAsset(silo0);
        TestStateLib.siloConfig().getFeesWithAsset(silo1);
    }
}
