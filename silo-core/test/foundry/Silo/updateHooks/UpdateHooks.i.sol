// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test --ffi -vv --mc UpdateHooksTest
*/
contract UpdateHooksTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    uint24 private _hooksBefore = 123;
    uint24 private _hooksAfter = 456;

    event HooksUpdated(uint24 hooksBefore, uint24 hooksAfter);

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    function hookReceiverConfig(address _silo) external view returns (uint24 hooksBefore, uint24 hooksAfter) {
        if (_silo == address(silo0)) return (0, 0);

        hooksBefore = _hooksBefore;
        hooksAfter = _hooksAfter;
    }

    /*
    forge test --ffi -vv --mt test_updateHooks_anyoneCanCall
    */
    function test_updateHooks_anyoneCanCall() public {
        vm.expectEmit(true, true, true, true);
        emit HooksUpdated(0, 0);

        silo1.updateHooks();
    }

    /*
    forge test --ffi -vv --mt test_updateHooks_emitEvent
    */
    function test_updateHooks_whenNothingChanged() public {
        // we expect not have reverts when no update was done
        silo0.updateHooks();

        vm.expectEmit(true, true, true, true);
        emit HooksUpdated(0, 0);

        silo0.updateHooks();

        silo1.updateHooks();

        vm.expectEmit(true, true, true, true);
        emit HooksUpdated(0, 0);

        silo1.updateHooks();
    }

    /*
    forge test --ffi -vv --mt test_updateHooks_pass
    */
    function test_updateHooks_pass() public {
        _mockHookReceiver(address(this));

        vm.expectEmit(true, true, true, true);
        emit HooksUpdated(_hooksBefore, _hooksAfter);

        silo1.updateHooks();

        uint24 expectedBefore = 123;
        uint24 expectedAfter = 456;

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo1));

        IShareToken.HookSetup memory hooks = IShareToken(protectedShareToken).hookSetup();
        assertEq(hooks.hooksBefore, expectedBefore, "protectedShareToken hooksBefore");
        assertEq(hooks.hooksAfter, expectedAfter, "protectedShareToken hooksAfter");
        assertEq(hooks.tokenType, Hook.PROTECTED_TOKEN, "protectedShareToken tokenType");

        hooks = IShareToken(collateralShareToken).hookSetup();
        assertEq(hooks.hooksBefore, expectedBefore, "collateralShareToken hooksBefore");
        assertEq(hooks.hooksAfter, expectedAfter, "collateralShareToken hooksAfter");
        assertEq(hooks.tokenType, Hook.COLLATERAL_TOKEN, "collateralShareToken tokenType");

        hooks = IShareToken(debtShareToken).hookSetup();
        assertEq(hooks.hooksBefore, expectedBefore, "debtShareToken hooksBefore");
        assertEq(hooks.hooksAfter, expectedAfter, "debtShareToken hooksAfter");
        assertEq(hooks.tokenType, Hook.DEBT_TOKEN, "debtShareToken tokenType");
    }

    /*
    forge test --ffi -vv --mt test_updateHooks_reset
    */
    function test_updateHooks_reset() public {
        _mockHookReceiver(address(this));

        silo1.updateHooks();

        // reset
        _hooksAfter = 0;
        _hooksBefore = 0;

        vm.expectEmit(true, true, true, true);
        emit HooksUpdated(0, 0);

        silo1.updateHooks();

        // restore
        _hooksAfter = 456;
        _hooksBefore = 123;

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo1));

        IShareToken.HookSetup memory hooks = IShareToken(protectedShareToken).hookSetup();
        assertEq(hooks.hooksBefore, 0, "protectedShareToken hooksBefore");
        assertEq(hooks.hooksAfter, 0, "protectedShareToken hooksAfter");

        hooks = IShareToken(collateralShareToken).hookSetup();
        assertEq(hooks.hooksBefore, 0, "collateralShareToken hooksBefore");
        assertEq(hooks.hooksAfter, 0, "collateralShareToken hooksAfter");

        hooks = IShareToken(debtShareToken).hookSetup();
        assertEq(hooks.hooksBefore, 0, "debtShareToken hooksBefore");
        assertEq(hooks.hooksAfter, 0, "debtShareToken hooksAfter");
    }

    function _mockHookReceiver(address _hookReceiver) internal {
        ISiloConfig.ConfigData memory mockedCfg0 = siloConfig.getConfig(address(silo0));
        ISiloConfig.ConfigData memory mockedCfg1 = siloConfig.getConfig(address(silo1));

        mockedCfg0.hookReceiver = _hookReceiver;
        mockedCfg1.hookReceiver = _hookReceiver;

        vm.mockCall(
            address(siloConfig),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, address(silo0)),
            abi.encode(mockedCfg0)
        );

        vm.mockCall(
            address(siloConfig),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, address(silo1)),
            abi.encode(mockedCfg1)
        );
    }
}
