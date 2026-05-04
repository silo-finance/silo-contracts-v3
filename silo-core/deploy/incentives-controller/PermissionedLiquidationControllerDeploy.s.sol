// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {console2} from "forge-std/console2.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationControllerFactory.sol";

/*
    SILO=0xe394050D179b72197A458Fdfb962Ae69908Aa5A0 \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationControllerDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify
 */
contract PermissionedLiquidationControllerDeploy is CommonDeploy {
    error FactoryNotFound();

    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        ISilo silo = ISilo(vm.envAddress("SILO"));

        address notifier = IShareToken(address(silo)).hookReceiver();
        address owner = Ownable(notifier).owner();

        address factory = SiloCoreDeployments.get(
            SiloCoreContracts.PERMISSIONED_LIQUIDATION_CONTROLLER_FACTORY, ChainsLib.chainAlias()
        );

        require(factory != address(0), FactoryNotFound());

        ISiloConfig cfg = silo.config();

        console2.log("SILO ID:", cfg.SILO_ID());

        ISiloConfig.ConfigData memory config = cfg.getConfig(address(silo));
        address collateralShareTokenAddress = config.collateralShareToken;
        address protectedShareTokenAddress = config.protectedShareToken;

        vm.startBroadcast(deployerPrivateKey);

        address incentivesControllerC =
            IPermissionedLiquidationControllerFactory(factory).create(IShareToken(collateralShareTokenAddress));
        
        address incentivesControllerP =
            IPermissionedLiquidationControllerFactory(factory).create(IShareToken(protectedShareTokenAddress));

        vm.stopBroadcast();

        // hook receiver ownership acceptance data
        console2.log(
            "\nHook(%s).setGauge(ic: %s, shareToken: %s)",
            notifier,
            incentivesControllerC,
            collateralShareTokenAddress
        );
        
        console2.log(
            "\nHook(%s).setGauge(ic: %s, shareToken: %s)", notifier, incentivesControllerP, protectedShareTokenAddress
        );

        console2.log("QA ---");

        vm.startPrank(owner);
        IGaugeHookReceiver(notifier)
            .setGauge(
                ISiloIncentivesController(address(incentivesControllerC)), IShareToken(collateralShareTokenAddress)
            );

        IGaugeHookReceiver(notifier)
            .setGauge(
                ISiloIncentivesController(address(incentivesControllerP)), IShareToken(protectedShareTokenAddress)
            );

        IGaugeHookReceiver(notifier).removeGauge(IShareToken(collateralShareTokenAddress));
        IGaugeHookReceiver(notifier).removeGauge(IShareToken(protectedShareTokenAddress));

        vm.stopPrank();

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(), _shareToken: collateralShareTokenAddress, _deployed: incentivesControllerC
        });

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(), _shareToken: protectedShareTokenAddress, _deployed: incentivesControllerP
        });
    }
}
