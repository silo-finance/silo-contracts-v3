// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";
import {ConstantReentrancyTest} from "./_ConstantReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract DefaultAdminRoleReentrancyTest is ConstantReentrancyTest {
    function methodDescription() external pure override returns (string memory description) {
        description = "DEFAULT_ADMIN_ROLE()";
    }

    function _ensureItWillNotRevert() internal view override {
        SiloHookV2(TestStateLib.hookReceiver()).DEFAULT_ADMIN_ROLE();
    }
}
