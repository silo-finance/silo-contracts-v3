// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ISiloLens} from "silo-core/contracts/interfaces/ISiloLens.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloLensDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloLensDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume

    remember to run `TowerRegistration` script after deployment!
 */
contract SiloLensDeploy is CommonDeploy {
    function run() public returns (ISiloLens siloLens) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        siloLens = ISiloLens(address(new SiloLens()));

        vm.stopBroadcast();

        console2.log("\n\tSiloLens redeployed - remember to run `TowerRegistration` script\n");

        _registerDeployment(address(siloLens), SiloCoreContracts.SILO_LENS);
    }
}
