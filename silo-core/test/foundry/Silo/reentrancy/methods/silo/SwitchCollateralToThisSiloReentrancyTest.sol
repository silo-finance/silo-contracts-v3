// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract SwitchCollateralToThisSiloReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo0.switchCollateralToThisSilo();
    }

    function verifyReentrancy() external {
        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo0.switchCollateralToThisSilo();

        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo1.switchCollateralToThisSilo();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "switchCollateralToThisSilo()";
    }
}
