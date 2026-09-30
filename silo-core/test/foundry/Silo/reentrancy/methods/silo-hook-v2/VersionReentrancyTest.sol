// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ConstantReentrancyTest} from "./_ConstantReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

contract VersionReentrancyTest is ConstantReentrancyTest {
    function methodDescription() external pure override returns (string memory description) {
        description = "VERSION()";
    }

    function _ensureItWillNotRevert() internal view override {
        IVersioned(TestStateLib.hookReceiver()).VERSION();
    }
}
