// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SiloVaultsContracts} from "silo-vaults/common/SiloVaultsContracts.sol";

import {SiloVaultsFactory, ISiloVaultsFactory} from "../contracts/SiloVaultsFactory.sol";

import {CommonDeploy} from "./common/CommonDeploy.sol";

/*
    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/SiloVaultsFactoryDeploy.s.sol:SiloVaultsFactoryDeploy \
        --ffi --rpc-url $RPC_INK --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/SiloVaultsFactoryDeploy.s.sol:SiloVaultsFactoryDeploy \
        --ffi --rpc-url $RPC_INK \
        --verify \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --private-key $PRIVATE_KEY \
        --resume

    FOUNDRY_PROFILE=vaults forge verify-contract 0x68D9ddfCBa478Fb56019a30CdF5A37788Af163Ac \
        --rpc-url $RPC_INJECTIVE \
        silo-vaults/contracts/SiloVault.sol:SiloVault \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch
*/
contract SiloVaultsFactoryDeploy is CommonDeploy {
    function run() public returns (SiloVaultsFactory siloVaultsFactory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        siloVaultsFactory = new SiloVaultsFactory();

        vm.stopBroadcast();

        _registerDeployment(address(siloVaultsFactory), SiloVaultsContracts.SILO_VAULTS_FACTORY);
    }
}
