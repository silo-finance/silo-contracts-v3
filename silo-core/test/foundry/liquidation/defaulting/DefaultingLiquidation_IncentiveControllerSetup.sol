// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";

import {SiloIncentivesControllerCompatible} from
    "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";

import {CloneHookV2} from "./common/CloneHookV2.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingLiquidation_IncentiveControllerSetupTest -vv
*/
contract DefaultingLiquidation_IncentiveControllerSetupTest is CloneHookV2 {
    ISiloIncentivesController gauge;

    function setUp() public view {
        require(silo0 == collateralShareToken, "silo0 must be collateralShareToken");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateControllerForCollateral_EmptyCollateralShareToken -vv
    */
    function test_validateControllerForCollateral_EmptyCollateralShareToken() public {
        ISiloConfig.ConfigData memory config;
        defaulting = _cloneHook(config, config);

        vm.mockCall(
            address(siloConfig),
            abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, silo0),
            abi.encode(address(0), address(0), address(0))
        );

        vm.expectRevert(IPartialLiquidationByDefaulting.EmptyCollateralShareToken.selector);
        defaulting.validateControllerForCollateral(silo0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateControllerForCollateral_NoControllerForCollateral -vv
    */
    function test_validateControllerForCollateral_NoControllerForCollateral() public {
        ISiloConfig.ConfigData memory config;
        defaulting = _cloneHook(config, config);

        _mockGetShareTokens();

        vm.expectRevert(IPartialLiquidationByDefaulting.NoControllerForCollateral.selector);
        defaulting.validateControllerForCollateral(silo0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateControllerForCollateral_pass -vv
    */
    function test_validateControllerForCollateral_pass() public {
        ISiloConfig.ConfigData memory config;
        defaulting = _cloneHook(config, config);

        _mockGetShareTokens();

        gauge = new SiloIncentivesControllerCompatible(address(this), address(defaulting), collateralShareToken);

        _setGauge(gauge, collateralShareToken);

        defaulting.validateControllerForCollateral(silo0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_validateControllerForCollateral_revertsWhenShareTokenDoesNotMatch -vv
    */
    function test_validateControllerForCollateral_revertsWhenShareTokenDoesNotMatch() public {
        ISiloConfig.ConfigData memory config;
        defaulting = _cloneHook(config, config);

        _mockGetShareTokens();

        gauge = new SiloIncentivesControllerCompatible(address(this), address(defaulting), collateralShareToken);
        _setGauge(gauge, collateralShareToken);

        vm.expectRevert(IPartialLiquidationByDefaulting.NoControllerForCollateral.selector);
        defaulting.validateControllerForCollateral(silo1);

        vm.expectRevert();
        defaulting.validateControllerForCollateral(protectedShareToken);

        vm.expectRevert();
        defaulting.validateControllerForCollateral(debtShareToken);
    }

    function _setGauge(ISiloIncentivesController _gauge, address _collateralShareToken) internal {
        address owner = Ownable(address(defaulting)).owner();
        vm.prank(owner);
        IGaugeHookReceiver(address(defaulting)).setGauge(_gauge, IShareToken(_collateralShareToken));
    }
}
