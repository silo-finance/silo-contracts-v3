// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {HookReceiverMock} from "silo-core/test/foundry/_mocks/HookReceiverMock.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ContractThatAcceptsETH} from "silo-core/test/foundry/_mocks/ContractThatAcceptsETH.sol";
import {SiloStorageExtension} from "silo-core/test/foundry/_mocks/SiloStorageExtension.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mc SiloHooksTest
*/
contract SiloHooksTest is SiloLittleHelper, Test {
    uint24 constant HOOKS_BEFORE = 1;
    uint24 constant HOOKS_AFTER = 2;

    SiloFixture internal _siloFixture;
    HookReceiverMock internal _hookReceiverMock;
    ISiloConfig internal _siloConfig;

    address internal _thridParty = makeAddr("ThirdParty");
    address internal _hookReceiverAddr;

    address internal timelock = makeAddr("Timelock");
    address internal feeDistributor = makeAddr("FeeDistributor");

    function setUp() public {
        _siloFixture = new SiloFixture();
        SiloConfigOverride memory configOverride;

        _hookReceiverMock = new HookReceiverMock(address(0));
        _hookReceiverMock.hookReceiverConfigMock(HOOKS_BEFORE, HOOKS_AFTER);

        _hookReceiverAddr = _hookReceiverMock.ADDRESS();

        configOverride.token0 = makeAddr("token0");
        configOverride.token1 = makeAddr("token1");
        configOverride.hookReceiver = _hookReceiverAddr;
        configOverride.configName = SiloConfigsNames.SILO_LOCAL_DEPLOYER;

        (_siloConfig, silo0, silo1,,,) = _siloFixture.deploy_local(configOverride);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testHooksInitializationAfterDeployment
    */
    function testHooksInitializationAfterDeployment() public view {
        IShareToken.HookSetup memory silo0Hooks = IShareToken(address(silo0)).hookSetup();

        assertEq(silo0Hooks.hooksBefore, HOOKS_BEFORE, "hooksBefore is not initialized");
        assertEq(silo0Hooks.hooksAfter, HOOKS_AFTER, "hooksAfter is not initialized");

        IShareToken.HookSetup memory silo1Hooks = IShareToken(address(silo1)).hookSetup();

        assertEq(silo1Hooks.hooksBefore, HOOKS_BEFORE, "hooksBefore is not initialized");
        assertEq(silo1Hooks.hooksAfter, HOOKS_AFTER, "hooksAfter is not initialized");
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testHooksUpdate
    function testHooksUpdate() public {
        uint24 newHooksBefore = 3;
        uint24 newHooksAfter = 4;

        _hookReceiverMock.hookReceiverConfigMock(newHooksBefore, newHooksAfter);

        silo0.updateHooks();

        IShareToken.HookSetup memory silo0Hooks = IShareToken(address(silo0)).hookSetup();

        assertEq(silo0Hooks.hooksBefore, newHooksBefore, "hooksBefore is not updated");
        assertEq(silo0Hooks.hooksAfter, newHooksAfter, "hooksAfter is not updated");

        silo1.updateHooks();

        IShareToken.HookSetup memory silo1Hooks = IShareToken(address(silo1)).hookSetup();

        assertEq(silo1Hooks.hooksBefore, newHooksBefore, "hooksBefore is not updated");
        assertEq(silo1Hooks.hooksAfter, newHooksAfter, "hooksAfter is not updated");
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testCallOnBehalfOfSilo
    function testCallOnBehalfOfSilo() public {
        (address protectedShareToken,,) = _siloConfig.getShareTokens(address(silo0));

        uint256 tokensToMint = 100;
        bytes memory data =
            abi.encodeWithSelector(IShareToken.mint.selector, _thridParty, _thridParty, tokensToMint);

        uint256 amountOfEth = 0;

        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        silo0.callOnBehalfOfSilo(protectedShareToken, amountOfEth, ISilo.CallType.Call, data);

        assertEq(IERC20(protectedShareToken).balanceOf(_thridParty), 0);

        vm.prank(_hookReceiverAddr);
        silo0.callOnBehalfOfSilo(protectedShareToken, amountOfEth, ISilo.CallType.Call, data);

        assertEq(IERC20(protectedShareToken).balanceOf(_thridParty), tokensToMint);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testCallOnBehalfOfSiloWithETH
    function testCallOnBehalfOfSiloWithETH() public {
        address target = address(new ContractThatAcceptsETH());
        bytes memory data = abi.encodeWithSelector(ContractThatAcceptsETH.anyFunction.selector);

        assertEq(target.balance, 0, "Expect to have no balance");

        uint256 amoutToSend = 1 ether;

        vm.deal(_hookReceiverAddr, amoutToSend);
        vm.prank(_hookReceiverAddr);
        silo0.callOnBehalfOfSilo{value: amoutToSend}(target, amoutToSend, ISilo.CallType.Call, data);

        assertEq(target.balance, amoutToSend, "Expect to have non zero balance");
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testSiloStorageMutationWithSiloExtension
    function testSiloStorageMutationWithSiloExtension() public {
        uint256 amoutToSend = 0;
        ISilo.AssetType assetType = ISilo.AssetType.Collateral;
        uint256 expectedTotalCollateralAssets = 1_9999_9999e18;

        address target = address(new SiloStorageExtension());

        bytes memory data = abi.encodeWithSelector(
            SiloStorageExtension.siloStorageMutation.selector, assetType, expectedTotalCollateralAssets
        );

        uint256 totalCollateralBeforeCall = silo0.getTotalAssetsStorage(assetType);
        assertEq(totalCollateralBeforeCall, 0, "Expect to have no collateral assets");

        vm.prank(_hookReceiverAddr);
        silo0.callOnBehalfOfSilo(target, amoutToSend, ISilo.CallType.Delegatecall, data);

        uint256 totalCollateralAfterCall = silo0.getTotalAssetsStorage(assetType);
        assertEq(totalCollateralAfterCall, expectedTotalCollateralAssets, "Expect to have collateral assets");
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testCallOnBehalfOfSiloWithETHleftover
    function testCallOnBehalfOfSiloWithETHleftover() public {
        address target = address(new ContractThatAcceptsETH());
        bytes memory data = abi.encodeWithSelector(ContractThatAcceptsETH.anyFunctionThatSendEthBack.selector);

        assertEq(target.balance, 0, "Expect to have no balance");

        uint256 amoutToSend = 1 ether;

        vm.deal(_hookReceiverAddr, amoutToSend);
        vm.prank(_hookReceiverAddr);
        silo0.callOnBehalfOfSilo{value: amoutToSend}(target, amoutToSend, ISilo.CallType.Call, data);

        assertEq(address(silo0).balance, amoutToSend, "Expect to have non zero balance");

        // transfer ether leftover in a separate transaction
        assertEq(_hookReceiverAddr.balance, 0, "Expect to have no balance on a hook receiver");

        bytes memory emptyPayload;

        vm.prank(_hookReceiverAddr);
        silo0.callOnBehalfOfSilo{value: 0}(_hookReceiverAddr, amoutToSend, ISilo.CallType.Call, emptyPayload);

        assertEq(_hookReceiverAddr.balance, amoutToSend, "Expect to have non zero balance on a hook receiver");
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testHooksMisconfiguration
    function testHooksMisconfiguration() public {
        vm.expectRevert(ISiloDeployer.HookReceiverMisconfigured.selector);
        _siloFixture.deploy_local(SiloConfigsNames.SILO_LOCAL_HOOKS_MISCONFIGURATION);
    }
}
