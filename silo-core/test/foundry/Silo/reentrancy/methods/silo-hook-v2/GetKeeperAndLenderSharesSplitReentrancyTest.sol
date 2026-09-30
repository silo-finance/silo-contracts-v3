// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ConstantReentrancyTest} from "./_ConstantReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract GetKeeperAndLenderSharesSplitReentrancyTest is ConstantReentrancyTest {
    function methodDescription() external pure override returns (string memory description) {
        description = "getKeeperAndLenderSharesSplit(uint256,uint8)";
    }

    function _ensureItWillNotRevert() internal view override {
        SiloHookV2(TestStateLib.hookReceiver()).getKeeperAndLenderSharesSplit(100, ISilo.CollateralType.Collateral);
        SiloHookV2(TestStateLib.hookReceiver()).getKeeperAndLenderSharesSplit(100, ISilo.CollateralType.Protected);
    }
}
