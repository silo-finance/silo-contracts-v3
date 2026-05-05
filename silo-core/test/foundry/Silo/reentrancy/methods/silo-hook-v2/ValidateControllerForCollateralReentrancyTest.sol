// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract ValidateControllerForCollateralReentrancyTest is MethodReentrancyTest {
    function callMethod() external view {
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure override returns (string memory description) {
        description = "validateControllerForCollateral(address)";
    }

    function _ensureItWillNotRevert() internal view {
        address silo0 = address(TestStateLib.silo0());
        address silo1 = address(TestStateLib.silo1());
        IPartialLiquidationByDefaulting hook = _getHook();

        hook.validateControllerForCollateral(silo0);
        hook.validateControllerForCollateral(silo1);
    }

    function _getHook() internal view returns (IPartialLiquidationByDefaulting) {
        return IPartialLiquidationByDefaulting(TestStateLib.hookReceiver());
    }
}
