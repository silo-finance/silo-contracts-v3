// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";

import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {console2} from "forge-std/console2.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloIncentivesControllerCreate} from "./SiloIncentivesControllerCreate.s.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {
    PermissionedLiquidationIncentiveController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationIncentiveController.sol";

/*
    SILO=0xe394050D179b72197A458Fdfb962Ae69908Aa5A0 \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedControllerDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify
 */
contract PermissionedControllerDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        ISilo silo = ISilo(vm.envAddress("SILO"));

        address notifier = IShareToken(address(silo)).hookReceiver();
        address owner = Ownable(notifier).owner();
        ISiloConfig cfg = silo.config();
        
        console2.log("SILO ID:", cfg.SILO_ID());

        ISiloConfig.ConfigData memory config = cfg.getConfig(address(silo));
        address collateralShareTokenAddress = config.collateralShareToken;
        address protectedShareTokenAddress = config.protectedShareToken;

        vm.startBroadcast(deployerPrivateKey);

        PermissionedLiquidationIncentiveController incentivesControllerC =
            new PermissionedLiquidationIncentiveController(owner, notifier, collateralShareTokenAddress);
        
        PermissionedLiquidationIncentiveController incentivesControllerP =
            new PermissionedLiquidationIncentiveController(owner, notifier, protectedShareTokenAddress);

        vm.stopBroadcast();

        // hook receiver ownership acceptance data
        console2.log(
            "\nHook(%s).setGauge(ic: %s, shareToken: %s)",
            notifier,
            address(incentivesControllerC),
            collateralShareTokenAddress
        );
        console2.log(
            "\nHook(%s).setGauge(ic: %s, shareToken: %s)",
            notifier,
            address(incentivesControllerP),
            protectedShareTokenAddress
        );

        console2.log("QA ---");

        vm.startPrank(owner);
        IGaugeHookReceiver(notifier)
            .setGauge(ISiloIncentivesController(incentivesControllerC), IShareToken(collateralShareTokenAddress));

        IGaugeHookReceiver(notifier)
            .setGauge(ISiloIncentivesController(incentivesControllerP), IShareToken(protectedShareTokenAddress));

        IGaugeHookReceiver(notifier).removeGauge(IShareToken(collateralShareTokenAddress));
        IGaugeHookReceiver(notifier).removeGauge(IShareToken(protectedShareTokenAddress));

        vm.stopPrank();

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(),
            _shareToken: collateralShareTokenAddress,
            _deployed: address(incentivesControllerC)
        });

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(),
            _shareToken: protectedShareTokenAddress,
            _deployed: address(incentivesControllerP)
        });
    }
}
