// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloVaultsContracts, SiloVaultsDeployments} from "silo-vaults/common/SiloVaultsContracts.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";

import {ISiloVaultsFactory} from "silo-vaults/contracts/interfaces/ISiloVaultsFactory.sol";
import {IdleVaultsFactory} from "silo-vaults/contracts/IdleVaultsFactory.sol";

import {
    ISiloIncentivesControllerFactory
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";

import {
    ISiloIncentivesControllerCLFactory
} from "silo-vaults/contracts/interfaces/ISiloIncentivesControllerCLFactory.sol";

import {ISiloVaultDeployer} from "silo-vaults/contracts/interfaces/ISiloVaultDeployer.sol";
import {SiloVaultDeployer} from "silo-vaults/contracts/SiloVaultDeployer.sol";

import {CommonDeploy} from "./common/CommonDeploy.sol";

/*
FOUNDRY_PROFILE=vaults \
    forge script silo-vaults/deploy/SiloVaultsDeployerDeploy.s.sol:SiloVaultsDeployerDeploy \
    --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify

Resume verification:
FOUNDRY_PROFILE=vaults \
    forge script silo-vaults/deploy/SiloVaultsDeployerDeploy.s.sol:SiloVaultsDeployerDeploy \
    --ffi --rpc-url $RPC_INJECTIVE \
    --verify \
    --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE \
    --private-key $PRIVATE_KEY \
    --resume

Deployed smart contracts verification:

- IdleVault from the CreateIdleVault event
    FOUNDRY_PROFILE=vaults forge verify-contract <contract_address> \
        silo-vaults/contracts/IdleVault.sol:IdleVault \
        --constructor-args <cast abi-encode output> \
        --compiler-version 0.8.28 \
        --rpc-url $RPC_SONIC \
        --watch

- SiloVault from the CreateSiloVault event
    FOUNDRY_PROFILE=vaults forge verify-contract <contract_address> \
        silo-vaults/contracts/SiloVault.sol:SiloVault \
        --libraries silo-vaults/contracts/libraries/SiloVaultActionsLib.sol:SiloVaultActionsLib:<lib_address> \
        --constructor-args <cast abi-encode output> \
        --compiler-version 0.8.28 \
        --rpc-url $RPC_SONIC \
        --watch

- IncentivesController from the CreateSiloVault event
    FOUNDRY_PROFILE=core forge verify-contract <contract_address> \
        silo-core/contracts/incentives/SiloIncentivesController.sol:SiloIncentivesController \
        --constructor-args <cast abi-encode output> \
        --compiler-version 0.8.28 \
        --rpc-url $RPC_SONIC \
        --watch
*/
contract SiloVaultsDeployerDeploy is CommonDeploy {
    function run() public returns (ISiloVaultDeployer deployer) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        string memory chainAlias = ChainsLib.chainAlias();

        ISiloIncentivesControllerFactory siloIncentivesControllerFactory = ISiloIncentivesControllerFactory(
            SiloCoreDeployments.get(SiloCoreContracts.INCENTIVES_CONTROLLER_FACTORY, chainAlias)
        );

        ISiloIncentivesControllerCLFactory siloIncentivesControllerCLFactory = ISiloIncentivesControllerCLFactory(
            SiloVaultsDeployments.get(SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY, chainAlias)
        );

        IdleVaultsFactory idleVaultsFactory = IdleVaultsFactory(
            SiloVaultsDeployments.get(SiloVaultsContracts.IDLE_VAULTS_FACTORY, chainAlias)
        );

        ISiloVaultsFactory siloVaultsFactory = ISiloVaultsFactory(
            SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULTS_FACTORY, chainAlias)
        );

        vm.startBroadcast(deployerPrivateKey);

        deployer = ISiloVaultDeployer(address(new SiloVaultDeployer(
            siloVaultsFactory,
            siloIncentivesControllerFactory,
            siloIncentivesControllerCLFactory,
            idleVaultsFactory
        )));

        vm.stopBroadcast();

        _registerDeployment(address(deployer), SiloVaultsContracts.SILO_VAULT_DEPLOYER);
    }
}
