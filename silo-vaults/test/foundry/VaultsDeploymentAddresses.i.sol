// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {ConstantsLib} from "../../contracts/libraries/ConstantsLib.sol";
import {ISiloVault} from "../../contracts/interfaces/ISiloVault.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc VaultsDeploymentAddressesTest -vvv
*/
contract VaultsDeploymentAddressesTest is IntegrationTest {
    function setUp() public {
        string memory _rpc = vm.envString("RPC_URL");

        vm.createSelectFork(_rpc);

        console2.log("block.timestamp", block.timestamp);
        console2.log("block.number", block.number);

        AddrLib.init();
    }

    function test_vaultDeployer_factory() public {
        ISiloVaultDeployer vaultDeployer = ISiloVaultDeployer(SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER));

        assertEq(vaultDeployer.SILO_VAULTS_FACTORY(), SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULTS_FACTORY), "SILO_VAULTS_FACTORY");
    }

    // SILO_INCENTIVES_CONTROLLER_FACTORY
    function test_vaultDeployer_incentivesControllerFactory() public {
        ISiloVaultDeployer vaultDeployer = ISiloVaultDeployer(SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER));

        assertEq(vaultDeployer.SILO_INCENTIVES_CONTROLLER_FACTORY(), SiloVaultsDeployments.get(SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_FACTORY), "SILO_INCENTIVES_CONTROLLER_FACTORY");
    }

    // SILO_INCENTIVES_CONTROLLER_CL_FACTORY
    function test_vaultDeployer_incentivesControllerCLFactory() public {
        ISiloVaultDeployer vaultDeployer = ISiloVaultDeployer(SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER));

        assertEq(vaultDeployer.SILO_INCENTIVES_CONTROLLER_CL_FACTORY(), SiloVaultsDeployments.get(SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY), "SILO_INCENTIVES_CONTROLLER_CL_FACTORY");
    }
    
    // IDLE_VAULTS_FACTORY
    function test_vaultDeployer_idleVaultsFactory() public {
        ISiloVaultDeployer vaultDeployer = ISiloVaultDeployer(SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER));

        assertEq(vaultDeployer.IDLE_VAULTS_FACTORY(), SiloVaultsDeployments.get(SiloVaultsContracts.IDLE_VAULTS_FACTORY), "IDLE_VAULTS_FACTORY");
    }
}
