// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {console2} from "forge-std/console2.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloIncentivesControllerCreate} from "./SiloIncentivesControllerCreate.s.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloIncentivesControllerFactory} from "silo-core/contracts/incentives/SiloIncentivesControllerFactory.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";

import {SiloDeployments} from "silo-core/deploy/silo/SiloDeployments.sol";

/*
    SILO=Test_Silo_WETH_USDC_id_3001 \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/SiloIncentivesControllerDefaulting.s.sol:SiloIncentivesControllerDefaulting \
        --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify

    // verify SiloIncentiveController:
    FOUNDRY_PROFILE=core \
        forge verify-contract --watch --rpc-url $RPC_ARBITRUM \
        0xFA7E04Dd205619644269eaA9846b0E267E859A14 \
        silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol:SiloIncentivesControllerCompatible \
        --constructor-args $(cast abi-encode "constructor(address,address,address)" \
        0xAaD2F138Eb20fb60C34ac70624339ccbaC2320fa 0x2174557e5ed2E8256284A5DF42A91b21db6313a9 0xe42E547c9c46c7b2bAd4914228699c0E09C1034D)
 */
contract SiloIncentivesControllerDefaulting is CommonDeploy {
    error NotHookReceiverOwner();

    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        address factory = SiloCoreDeployments.get(
            SiloCoreContracts.INCENTIVES_CONTROLLER_FACTORY,
            ChainsLib.chainAlias()
        );

        string memory siloKey = vm.envString("SILO");
        address siloConfig = SiloDeployments.get(ChainsLib.chainAlias(), siloKey);
        require(siloConfig != address(0), "silo not found");

        (address silo0, address silo1) = ISiloConfig(siloConfig).getSilos();
        ISiloConfig.ConfigData memory config0 = ISiloConfig(siloConfig).getConfig(silo0);
        ISiloConfig.ConfigData memory config1 = ISiloConfig(siloConfig).getConfig(silo1);
        
        address hookReceiver = config0.hookReceiver;

        address shareToken = config0.lt == 0 ? silo0 : silo1;

        require(Ownable(hookReceiver).owner() == deployer, NotHookReceiverOwner());

        vm.startBroadcast(deployerPrivateKey);

        address incentivesController = SiloIncentivesControllerFactory(factory).create({
            _owner: deployer,
            _notifier: hookReceiver,
            _shareToken: shareToken,
            _externalSalt: bytes32(0)
        });

        IGaugeHookReceiver(hookReceiver).setGauge(
            ISiloIncentivesController(incentivesController), IShareToken(shareToken)
        );

        vm.stopBroadcast();

       IPartialLiquidationByDefaulting(hookReceiver).validateControllerForCollateral(shareToken);

       console2.log("Incentives controller created:", incentivesController);
       console2.log("Hook receiver:", hookReceiver);
       console2.log("Share token / silo", shareToken);
    }
}
