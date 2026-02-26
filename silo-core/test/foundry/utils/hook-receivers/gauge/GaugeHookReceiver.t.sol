// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";

import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";
import {TransferOwnership} from "../../../_common/TransferOwnership.sol";

// FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc GaugeHookReceiverTest
contract GaugeHookReceiverTest is SiloLittleHelper, Test, TransferOwnership {
    IGaugeHookReceiver internal _hookReceiver;
    ISiloConfig internal _siloConfig;

    uint256 internal constant _SENDER_BAL = 1;
    uint256 internal constant _RECIPIENT_BAL = 1;
    uint256 internal constant _TS = 1;
    uint256 internal constant _AMOUNT = 0;

    address internal _sender = makeAddr("Sender");
    address internal _recipient = makeAddr("Recipient");
    address internal _dao;
    address internal _gauge = makeAddr("Gauge");
    address internal _gauge2 = makeAddr("Gauge2");

    address internal feeDistributor = makeAddr("FeeDistributor");

    event GaugeConfigured(address gauge, address shareToken);

    function setUp() public {
        _siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_GAUGE_HOOK_RECEIVER);

        IHookReceiver hook = IHookReceiver(IShareToken(address(silo0)).hookSetup().hookReceiver);

        _hookReceiver = IGaugeHookReceiver(address(hook));

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        _dao = deployer;
    }

    // FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt testReInitialization
    function testReInitialization() public {
        address hookReceiverImpl = AddrLib.getAddress(SiloCoreContracts.SILO_HOOK_V1);

        bytes memory data = abi.encode(_dao);

        // Implementation is not initializable
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        IHookReceiver(hookReceiverImpl).initialize(ISiloConfig(address(0)), data);

        // Gauge hook receiver can't be re-initialized
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _hookReceiver.initialize(ISiloConfig(address(0)), data);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testHookReceiverInitialization
    function testHookReceiverInitialization() public view {
        (address silo0, address silo1) = _siloConfig.getSilos();

        _testHookReceiverInitializationForSilo(silo0);
        _testHookReceiverInitializationForSilo(silo1);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testHookReceiverTransferOwnership
    function testHookReceiverTransferOwnership() public {
        assertTrue(_test_transfer2StepOwnership(address(_hookReceiver), _dao));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testHookReceiverPermissions
    function testHookReceiverPermissions() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _hookReceiver.removeGauge(IShareToken(address(0)));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testSetGaugeValidation
    function testSetGaugeValidation() public {
        // Revert without reason as `_gauge` do not have `shareToken()` fn
        vm.expectRevert();
        vm.prank(_dao);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(address(0)));

        address invalidShareToken = makeAddr("InvalidShareToken");

        _mockGaugeShareToken(_gauge, invalidShareToken);

        vm.prank(_dao);
        vm.expectRevert(IGaugeHookReceiver.WrongGaugeShareToken.selector);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(address(1)));

        vm.prank(_dao);
        // Revert without reason as `invalidShareToken` do not have `silo()` fn
        vm.expectRevert();
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(invalidShareToken));

        (address silo0,) = _siloConfig.getSilos();

        bytes memory data = abi.encodePacked(IShareToken.silo.selector);
        vm.mockCall(invalidShareToken, data, abi.encode(silo0));
        vm.expectCall(invalidShareToken, data);

        vm.prank(_dao);
        vm.expectRevert(IGaugeHookReceiver.InvalidShareToken.selector);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(invalidShareToken));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testSetGaugePass
    */
    function testSetGaugePass() public {
        (address silo0, address silo1) = _siloConfig.getSilos();
        (, address shareCollateralToken,) = _siloConfig.getShareTokens(silo0);

        _mockGaugeShareToken(_gauge, shareCollateralToken);

        ISiloIncentivesController configured =
            GaugeHookReceiver(address(_hookReceiver)).configuredGauges(IShareToken(shareCollateralToken));

        assertEq(address(configured), address(0), "Gauge should not be configured");

        vm.prank(_dao);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(shareCollateralToken));

        configured =
            GaugeHookReceiver(address(_hookReceiver)).configuredGauges(IShareToken(shareCollateralToken));

        assertEq(address(configured), _gauge, "Gauge should be configured");

        _mockGaugeShareToken(_gauge2, shareCollateralToken);

        vm.prank(_dao);
        vm.expectRevert(IGaugeHookReceiver.GaugeAlreadyConfigured.selector);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge2), IShareToken(shareCollateralToken));

        (uint24 hooksBefore, uint24 hooksAfter) = _hookReceiver.hookReceiverConfig(silo0);

        uint256 action = Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN);

        assertEq(uint256(hooksBefore), 0, "Hooks before should be 0");
        assertEq(uint256(hooksAfter), action, "Hooks after should match action");

        IShareToken.HookSetup memory silo0Hooks = IShareToken(address(silo0)).hookSetup();

        assertEq(uint256(silo0Hooks.hooksBefore), 0, "[aster setup 0] hooks before should be 0");
        assertEq(uint256(silo0Hooks.hooksAfter), action, "[aster setup 0] hooks after should match action");

        IShareToken.HookSetup memory silo1Hooks = IShareToken(address(silo1)).hookSetup();

        assertEq(uint256(silo1Hooks.hooksBefore), 0, "[aster setup 1] hooks before should be 0");
        assertEq(uint256(silo1Hooks.hooksAfter), 0, "[aster setup 1] hooks after should be 0");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testRemoveGauge
    function testRemoveGauge() public {
        (address silo0, address silo1) = _siloConfig.getSilos();
        (, address shareCollateralToken,) = _siloConfig.getShareTokens(silo0);

        vm.prank(_dao);
        vm.expectRevert(IGaugeHookReceiver.GaugeIsNotConfigured.selector);
        _hookReceiver.removeGauge(IShareToken(shareCollateralToken));

        _mockGaugeShareToken(_gauge, shareCollateralToken);

        vm.prank(_dao);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(shareCollateralToken));

        (uint24 hooksBefore0, uint24 hooksAfter0) = _hookReceiver.hookReceiverConfig(silo0);

        IShareToken.HookSetup memory silo0HooksBefore = IShareToken(address(silo0)).hookSetup();
        IShareToken(address(silo1)).hookSetup();

        vm.prank(_dao);
        _hookReceiver.removeGauge(IShareToken(shareCollateralToken));

        IShareToken.HookSetup memory silo0HooksAfter = IShareToken(address(silo0)).hookSetup();
        IShareToken(address(silo1)).hookSetup();

        (uint24 hooksBefore1, uint24 hooksAfter1) = _hookReceiver.hookReceiverConfig(silo0);

        assertEq(uint256(hooksBefore0), uint256(hooksBefore1), "Hook setup should not change");
        assertEq(uint256(hooksAfter0), uint256(hooksAfter1), "Hook setup should not change");

        assertEq(
            uint256(silo0HooksBefore.hooksBefore),
            uint256(silo0HooksAfter.hooksBefore),
            "Silo0 hooks before should not change"
        );

        assertEq(
            uint256(silo0HooksAfter.hooksAfter),
            uint256(silo0HooksBefore.hooksAfter),
            "Silo0 hooks after should not change"
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testAfterTokenTransfer
    function testAfterTokenTransfer() public {
        (address silo0,) = _siloConfig.getSilos();
        (,, address debtShareToken) = _siloConfig.getShareTokens(silo0);

        _mockGaugeShareToken(_gauge, debtShareToken);

        vm.prank(_dao);
        _hookReceiver.setGauge(ISiloIncentivesController(_gauge), IShareToken(debtShareToken));

        uint256 action = Hook.shareTokenTransfer(Hook.DEBT_TOKEN);

        (, uint24 hooksAfter) = _hookReceiver.hookReceiverConfig(silo0);
        assertEq(uint256(hooksAfter), action);

        bytes memory data = _getEncodedData();

        vm.prank(debtShareToken);
        _hookReceiver.afterAction(silo0, action, data);

        // will do nothing as action didn't match
        uint256 invalidAction = Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN);
        vm.prank(debtShareToken);
        _hookReceiver.afterAction(silo0, invalidAction, data);
    }

    function _mockGaugeAfterTransfer() internal {
        bytes memory data = abi.encodeCall(
            ISiloIncentivesController.afterTokenTransfer,
            (_sender, _SENDER_BAL, _recipient, _RECIPIENT_BAL, _TS, _AMOUNT)
        );

        vm.mockCall(_gauge, data, abi.encode(true));
        vm.expectCall(_gauge, data);
    }

    function _getEncodedData() internal view returns (bytes memory) {
        return abi.encodePacked(_sender, _recipient, _AMOUNT, _SENDER_BAL, _RECIPIENT_BAL, _TS);
    }

    function _mockGaugeShareToken(address _gaugeToMock, address _tokenToSet) internal {
        bytes memory data = abi.encodePacked(ISiloIncentivesController.SHARE_TOKEN.selector);
        vm.mockCall(_gaugeToMock, data, abi.encode(_tokenToSet));
        vm.expectCall(_gaugeToMock, data);
    }

    function _testHookReceiverInitializationForSilo(address _silo) internal view {
        IHookReceiver hookReceiver = IHookReceiver(IShareToken(address(silo0)).hookSetup().hookReceiver);

        assertEq(address(hookReceiver), address(_hookReceiver));

        (address collateral, address protected, address debt) = _siloConfig.getShareTokens(_silo);

        _testHookReceiverForShareToken(collateral);
        _testHookReceiverForShareToken(protected);
        _testHookReceiverForShareToken(debt);
    }

    function _testHookReceiverForShareToken(address _siloShareToken) internal view {
        IShareToken.HookSetup memory hookSetup = IShareToken(_siloShareToken).hookSetup();
        assertEq(hookSetup.hookReceiver, address(_hookReceiver));
    }
}
