// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc SwitchCollateralToTest
*/
contract SwitchCollateralToTest is SiloLittleHelper, Test {
    function setUp() public {
        _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_switchCollateralToThisSilo_pass
    */
    function test_switchCollateralToThisSilo_pass() public {
        vm.expectRevert(ISilo.Deprecated.selector);
        silo0.switchCollateralToThisSilo();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo1.switchCollateralToThisSilo();
    }
}
