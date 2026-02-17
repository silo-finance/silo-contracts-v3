// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {SiloHookV3} from "silo-core/contracts/hooks/SiloHookV3.sol";

/*
    FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingLiquidationHookV3Test -vv
 */
contract DefaultingLiquidationHookV3Test is Test {
    function test_defaulting_onlyCDL() public {
        SiloHookV3 hook = new SiloHookV3();

        vm.expectRevert(SiloHookV3.NotSupported.selector);
        hook.liquidationCall(address(0), address(0), address(0), 0, false);
    }

    function test_defaulting_version() public {
        SiloHookV3 hook = new SiloHookV3();
        assertEq(hook.VERSION(), "SiloHookV3 4.0.0");
    }
}
