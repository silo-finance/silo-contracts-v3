// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";

import {
    SiloIncentivesControllerFactoryDeploy
} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {
    ISiloIncentivesControllerFactory
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";

/**
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloIncentivesControllerGaugeLikeIntegrationTest
 */
contract SiloIncentivesControllerGaugeLikeIntegrationTest is Test {
    ISiloIncentivesControllerFactory internal _factory;
    address internal _owner = makeAddr("Owner");

    error CantRemoveActiveGauge();

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), 366902426);

        SiloIncentivesControllerFactoryDeploy deploy = new SiloIncentivesControllerFactoryDeploy();
        deploy.disableDeploymentsSync();
        _factory = ISiloIncentivesControllerFactory(deploy.run());
    }

    /**
     FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_gaugeHookReceiver_connect_disconnect_gaugeLikeIncentives
     */
    function test_gaugeHookReceiver_connect_disconnect_gaugeLikeIncentives() public {
        ISiloConfig siloConfig = ISiloConfig(0x1Fc8Def96461d58E73b208fEBDC964eeaD07256d); // Silo_WBTC_USDC_V2
        (address silo0,) = siloConfig.getSilos();

        IGaugeHookReceiver gaugeHookReceiver = IGaugeHookReceiver(IShareToken(address(silo0)).hookSetup().hookReceiver);
        (,, address debtShareToken) = siloConfig.getShareTokens(silo0);

        address gaugeLikeController = _factory.create(_owner, address(gaugeHookReceiver), debtShareToken, bytes32(0));

        address hookOwner = Ownable(address(gaugeHookReceiver)).owner();

        vm.prank(hookOwner);
        gaugeHookReceiver.setGauge(ISiloIncentivesController(gaugeLikeController), IShareToken(debtShareToken));

        ISiloIncentivesController configured = GaugeHookReceiver(address(gaugeHookReceiver)).configuredGauges(
            IShareToken(debtShareToken)
        );

        assertEq(address(configured), address(gaugeLikeController));

        vm.prank(hookOwner);
        vm.expectRevert(abi.encodeWithSelector(CantRemoveActiveGauge.selector));
        gaugeHookReceiver.removeGauge(IShareToken(debtShareToken));

        vm.prank(_owner);
        SiloIncentivesControllerCompatible(gaugeLikeController).killGauge();

        vm.prank(hookOwner);
        gaugeHookReceiver.removeGauge(IShareToken(debtShareToken));

        assertEq(address(GaugeHookReceiver(address(gaugeHookReceiver)).configuredGauges(IShareToken(debtShareToken))), address(0));
    }
}
