// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Silo} from "silo-core/contracts/Silo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract AssetReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "asset()";
    }

    function _ensureItWillNotRevert() internal view {
        Silo silo0 = Silo(payable(address(TestStateLib.silo0())));
        Silo silo1 = Silo(payable(address(TestStateLib.silo1())));

        silo0.asset();
        silo1.asset();
    }
}
