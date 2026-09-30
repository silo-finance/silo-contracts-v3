// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloHookReceiverHarness} from "silo-core/test/foundry/_mocks/SiloHookReceiverHarness.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloHookReceiverTest
*/
contract SiloHookReceiverTest is Test {
    uint24 public constant HOOKS_BEFORE = 100;
    uint24 public constant HOOKS_AFTER = 200;

    address public silo = makeAddr("silo");
    SiloHookReceiverHarness public hookReceiver;

    event HookConfigured(address silo, uint24 hooksBefore, uint24 hooksAfter);

    function setUp() public {
        hookReceiver = new SiloHookReceiverHarness();

        vm.mockCall(silo, abi.encodeWithSelector(ISilo.updateHooks.selector), abi.encode(true));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_hookReceiver_setHookConfig
    */
    function test_hookReceiver_setHookConfig() public {
        vm.expectEmit(true, true, true, true);

        emit HookConfigured(silo, uint24(HOOKS_BEFORE), uint24(HOOKS_AFTER));

        hookReceiver.setHookConfig(silo, HOOKS_BEFORE, HOOKS_AFTER);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_hookReceiver_getters
    */
    function test_hookReceiver_getters() public {
        hookReceiver.setHookConfig(silo, HOOKS_BEFORE, HOOKS_AFTER);

        (uint24 hooksBefore, uint24 hooksAfter) = hookReceiver.hookReceiverConfig(silo);

        assertEq(hooksBefore, HOOKS_BEFORE);
        assertEq(hooksAfter, HOOKS_AFTER);

        assertEq(hookReceiver.getHooksBefore(silo), HOOKS_BEFORE);
        assertEq(hookReceiver.getHooksAfter(silo), HOOKS_AFTER);
    }
}
