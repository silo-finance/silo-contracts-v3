// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";
import {ConstantReentrancyTest} from "./_ConstantReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract GetRoleMemberCountReentrancyTest is ConstantReentrancyTest {
    function methodDescription() external pure override returns (string memory description) {
        description = "getRoleMemberCount(bytes32)";
    }

    function _ensureItWillNotRevert() internal view override {
        SiloHookV2(TestStateLib.hookReceiver()).getRoleMemberCount(bytes32(0));
        SiloHookV2(TestStateLib.hookReceiver()).getRoleMemberCount(bytes32("role"));
    }
}
