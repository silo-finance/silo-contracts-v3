// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingLiquidationInvalidConfig -vv
*/
contract DefaultingLiquidationInvalidConfigTest is Test {
    ISiloConfig siloConfig = ISiloConfig(makeAddr("siloConfig"));
    address silo0 = makeAddr("silo0");
    address silo1 = makeAddr("silo1");

    SiloHookV2 defaulting;

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_HookV2_version -vv
    */
    function test_HookV2_version() public {
        ISiloConfig.ConfigData memory config;
        _cloneHook(config).VERSION();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_twoWayMarket -vv
    */
    function test_defaulting_twoWayMarket() public {
        ISiloConfig.ConfigData memory config;
        config.maxLtv = 1;
        config.lt = 1;

        _mockSiloConfig(config, config);

        SiloHookV2 implementation = new SiloHookV2();
        defaulting = SiloHookV2(Clones.clone(address(implementation)));

        vm.expectRevert(IPartialLiquidationByDefaulting.TwoWayMarketNotAllowed.selector);
        defaulting.initialize(siloConfig, abi.encode(address(this)));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateDefaultingCollateral_TwoWayMarketNotAllowed -vv
    */
    function test_validateDefaultingCollateral_TwoWayMarketNotAllowed() public {
        ISiloConfig.ConfigData memory config;
        defaulting = _cloneHook(config);

        config.maxLtv = 1;
        config.lt = 1;
        _mockSiloConfig(config, config);

        vm.expectRevert(IPartialLiquidationByDefaulting.TwoWayMarketNotAllowed.selector);
        defaulting.validateDefaultingCollateral();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateDefaultingCollateral_UnnecessaryLiquidationFee -vv
    */
    function test_validateDefaultingCollateral_UnnecessaryLiquidationFee() public {
        ISiloConfig.ConfigData memory config0;
        ISiloConfig.ConfigData memory config1;

        config0.lt = 1;
        config1.lt = 0;

        defaulting = _cloneHook(config0, config1);

        config0.liquidationFee = 1;
        config1.liquidationFee = 1;
        _mockSiloConfig(config0, config1);

        vm.expectRevert(IPartialLiquidationByDefaulting.UnnecessaryLiquidationFee.selector);
        defaulting.validateDefaultingCollateral();

        config0.liquidationFee = 0;
        config1.liquidationFee = 1;
        _mockSiloConfig(config0, config1);

        vm.expectRevert(IPartialLiquidationByDefaulting.UnnecessaryLiquidationFee.selector);
        defaulting.validateDefaultingCollateral();

        // counterexample
        config0.liquidationFee = 1;
        config1.liquidationFee = 0;
        _mockSiloConfig(config0, config1);

        // pass
        defaulting.validateDefaultingCollateral();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateDefaultingCollateral_InvalidLT -vv
    */
    function test_validateDefaultingCollateral_InvalidLT() public {
        ISiloConfig.ConfigData memory config0;
        ISiloConfig.ConfigData memory config1;
        defaulting = _cloneHook(config0);

        config0.lt = 1e18 - defaulting.LT_MARGIN_FOR_DEFAULTING();
        _mockSiloConfig(config0, config1);

        vm.expectRevert(IPartialLiquidationByDefaulting.InvalidLTConfig0.selector);
        defaulting.validateDefaultingCollateral();

        config0.lt = 0;
        config1.liquidationFee = 1;
        config1.lt = 1e18 - defaulting.LT_MARGIN_FOR_DEFAULTING() - config1.liquidationFee + 1;
        _mockSiloConfig(config0, config1);

        vm.expectRevert(IPartialLiquidationByDefaulting.InvalidLTConfig1.selector);
        defaulting.validateDefaultingCollateral();

        // counterexample
        config0.lt = 0;
        config1.liquidationFee = 1;
        config1.lt = 1e18 - defaulting.LT_MARGIN_FOR_DEFAULTING() - config1.liquidationFee;
        _mockSiloConfig(config0, config1);

        // pass
        defaulting.validateDefaultingCollateral();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_hookv2_constructor_InvalidInitialization -vv
    */
    function test_hookv2_constructor_InvalidInitialization() public {
        defaulting = new SiloHookV2();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        defaulting.initialize(ISiloConfig(address(1)), abi.encode(address(this)));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_hookv2_initTwice_InvalidInitialization -vv
    */
    function test_hookv2_initTwice_InvalidInitialization() public {
        ISiloConfig.ConfigData memory config;
        defaulting = _cloneHook(config);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        defaulting.initialize(siloConfig, abi.encode(address(this)));
    }

    function _cloneHook(ISiloConfig.ConfigData memory _config) internal returns (SiloHookV2 hook) {
        return _cloneHook(_config, _config);
    }

    function _cloneHook(ISiloConfig.ConfigData memory _config0, ISiloConfig.ConfigData memory _config1)
        internal
        returns (SiloHookV2 hook)
    {
        SiloHookV2 implementation = new SiloHookV2();
        hook = SiloHookV2(Clones.clone(address(implementation)));

        _mockSiloConfig(_config0, _config1);

        hook.initialize(siloConfig, abi.encode(address(this)));
    }

    function _mockSiloConfig(ISiloConfig.ConfigData memory _config0, ISiloConfig.ConfigData memory _config1)
        internal
    {
        vm.mockCall(
            address(siloConfig), abi.encodeWithSelector(ISiloConfig.getSilos.selector), abi.encode(silo0, silo1)
        );

        vm.mockCall(
            address(siloConfig), abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0), abi.encode(_config0)
        );

        vm.mockCall(
            address(siloConfig), abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1), abi.encode(_config1)
        );
    }
}
