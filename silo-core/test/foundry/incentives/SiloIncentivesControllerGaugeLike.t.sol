// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {SiloLittleHelper} from "silo-core/test/foundry/_common/SiloLittleHelper.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";

import {
    SiloIncentivesControllerFactoryDeploy
} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {
    ISiloIncentivesControllerFactory
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {IDistributionManager} from "silo-core/contracts/incentives/interfaces/IDistributionManager.sol";

/**
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloIncentivesControllerGaugeLikeTest
 */
contract SiloIncentivesControllerGaugeLikeTest is SiloLittleHelper, Test {
    address internal _shareToken = address(new ERC20Mock());
    address internal _owner = makeAddr("Owner");
    address internal _notifier = address(new ERC20Mock());

    ISiloIncentivesControllerFactory internal _factory;

    event GaugeKilled();
    event GaugeUnKilled();

    function setUp() public {
        SiloIncentivesControllerFactoryDeploy deploy = new SiloIncentivesControllerFactoryDeploy();
        deploy.disableDeploymentsSync();
        _factory = ISiloIncentivesControllerFactory(deploy.run());
    }

    /**
     FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createGaugeLike
     */
    function test_createGaugeLike_success() public {
        address gaugeLike = _factory.create(_owner, _notifier, _shareToken, bytes32(0));
        assertTrue(_factory.isSiloIncentivesController(gaugeLike), "GaugeLike should be created in factory");
    }

    /**
     FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createGaugeLike_zeroShares
     */
    function test_createGaugeLike_zeroShares() public {
        vm.expectRevert(ISiloIncentivesController.EmptyShareToken.selector);
        _factory.create(_owner, _notifier, address(0), bytes32(0));
    }

    /**
     FOUNDRY_PROFILE=core_test forge test --ffi --mt test_afterTokenTransfer_onlyNotifier -vvv
     */
    function test_afterTokenTransfer_onlyNotifier() public {
        address gaugeLike = _factory.create(_owner, _notifier, _shareToken, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.OnlyNotifier.selector, address(this)));
        SiloIncentivesControllerCompatible(gaugeLike).afterTokenTransfer({
            _sender: address(this),
            _senderBalance: 1,
            _recipient: address(this),
            _recipientBalance: 1,
            _totalSupply: 1,
            _amount: 1
        });

        // crosscheck
        vm.prank(_notifier);
        SiloIncentivesControllerCompatible(gaugeLike).afterTokenTransfer({
            _sender: address(this),
            _senderBalance: 1,
            _recipient: address(this),
            _recipientBalance: 1,
            _totalSupply: 1,
            _amount: 1
        });
    }

    /**
     FOUNDRY_PROFILE=core_test forge test --ffi --mt test_killGauge_onlyOwner -vvv
     */
    function test_killGauge_onlyOwner() public {
        address gaugeLike = _factory.create(_owner, _notifier, _shareToken, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        SiloIncentivesControllerCompatible(gaugeLike).killGauge();
    }

    /**
     FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_unKillGauge_onlyOwner
     */
    function test_unKillGauge_onlyOwner() public {
        address gaugeLike = _factory.create(_owner, _notifier, _shareToken, bytes32(0));

        vm.prank(_owner);
        SiloIncentivesControllerCompatible(gaugeLike).killGauge();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        SiloIncentivesControllerCompatible(gaugeLike).unkillGauge();
    }

    /**
     FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_killGauge_success
     */
    function test_killGauge_success() public {
        address gaugeLike = _factory.create(_owner, _notifier, _shareToken, bytes32(0));

        assertFalse(SiloIncentivesControllerCompatible(gaugeLike).is_killed(), "GaugeLike should not be killed");

        vm.expectEmit(true, true, true, true);
        emit GaugeKilled();

        vm.prank(_owner);
        SiloIncentivesControllerCompatible(gaugeLike).killGauge();

        assertTrue(SiloIncentivesControllerCompatible(gaugeLike).is_killed(), "GaugeLike should be killed");
    }

    /**
     FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_unKillGauge_success
     */
    function test_unKillGauge_success() public {
        address gaugeLike = _factory.create(_owner, _notifier, _shareToken, bytes32(0));

        vm.prank(_owner);
        SiloIncentivesControllerCompatible(gaugeLike).killGauge();

        assertTrue(SiloIncentivesControllerCompatible(gaugeLike).is_killed(), "GaugeLike should be killed");

        vm.expectEmit(true, true, true, true);
        emit GaugeUnKilled();

        vm.prank(_owner);
        SiloIncentivesControllerCompatible(gaugeLike).unkillGauge();

        assertFalse(SiloIncentivesControllerCompatible(gaugeLike).is_killed(), "GaugeLike should not be killed");
    }

    /**
     FOUNDRY_PROFILE=core_test forge test --ffi --mt test_gaugeLikeIncentives_with_gaugeHookReceiver -vvv
     */
    function test_gaugeLikeIncentives_with_gaugeHookReceiver() public {
        ISiloConfig siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_GAUGE_HOOK_RECEIVER);
        (address silo0,) = siloConfig.getSilos();

        IGaugeHookReceiver gaugeHookReceiver = IGaugeHookReceiver(IShareToken(address(silo0)).hookSetup().hookReceiver);
        (,address shareCollateralToken,) = siloConfig.getShareTokens(silo0);

        address gaugeLikeController = _factory.create(_owner, _notifier, shareCollateralToken, bytes32(0));

        address hookOwner = Ownable(address(gaugeHookReceiver)).owner();

        vm.prank(hookOwner);
        gaugeHookReceiver.setGauge(ISiloIncentivesController(gaugeLikeController), IShareToken(shareCollateralToken));

        ISiloIncentivesController configured = GaugeHookReceiver(address(gaugeHookReceiver)).configuredGauges(
            IShareToken(shareCollateralToken)
        );

        assertEq(address(configured), address(gaugeLikeController));
    }
}
