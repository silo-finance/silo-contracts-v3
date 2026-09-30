// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc LiquidationWrongSiloTest
*/
contract LiquidationWrongInputsTest is SiloLittleHelper, Test {
    ISiloConfig internal _siloConfig;

    function setUp() public {
        _siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_liquidationInput_NoDebtToCover
    */
    function test_liquidationInput_NoDebtToCover() public {
        vm.expectRevert(IPartialLiquidation.NoDebtToCover.selector);

        partialLiquidation.liquidationCall(address(0), address(0), address(0), 0, false);
    }
}
