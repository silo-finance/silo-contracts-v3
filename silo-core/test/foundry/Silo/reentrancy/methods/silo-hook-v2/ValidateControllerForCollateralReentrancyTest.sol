// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract ValidateControllerForCollateralReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure override returns (string memory description) {
        description = "validateControllerForCollateral(address)";
    }

    function _ensureItWillNotRevert() internal {
        address silo0 = address(TestStateLib.silo0());
        address silo1 = address(TestStateLib.silo1());
        IPartialLiquidationByDefaulting hook = _getHook();

        // silo0 is debt silo
        hook.validateControllerForCollateral(silo0);

        vm.expectRevert(IPartialLiquidationByDefaulting.NoControllerForCollateral.selector);
        hook.validateControllerForCollateral(silo1);
    }

    function _getHook() internal view returns (IPartialLiquidationByDefaulting) {
        return IPartialLiquidationByDefaulting(TestStateLib.hookReceiver());
    }
}
