// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {Tower} from "silo-core/contracts/utils/Tower.sol";
import {
    SiloIncentivesControllerCompatible
} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

/*
    FOUNDRY_PROFILE=core \
    forge script silo-core/deploy/CodeVerificationDeploy.s.sol:CodeVerificationDeploy \
    --ffi --rpc-url $RPC_MAINNET --broadcast --verify


    in case verification fail, set `ETHERSCAN_API_KEY` in env and run:
    FOUNDRY_PROFILE=core \
    forge script silo-core/deploy/TowerDeploy.s.sol:TowerDeploy \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract CodeVerificationDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        ISiloConfig.ConfigData memory data;

        vm.startBroadcast(deployerPrivateKey);

        new SiloIncentivesControllerCompatible({
            _owner: address(1), _notifier: address(2), _shareTokenAddress: address(3)
        });

        new SiloConfig({_siloId: 0, _configData0: data, _configData1: data});

        vm.stopBroadcast();
    }
}
