// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloVaultsContracts, SiloVaultsDeployments} from "silo-vaults/common/SiloVaultsContracts.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {SiloVaultDeployer} from "silo-vaults/contracts/SiloVaultDeployer.sol";

/*
 FOUNDRY_PROFILE=vaults_tests RPC_URL=$RPC_INJECTIVE forge test --ffi --mc VaultsDeploymentAddressesTest -vvv
*/
contract VaultsDeploymentAddressesTest is Test {
    function setUp() public {
        string memory _rpc = vm.envString("RPC_URL");

        vm.createSelectFork(_rpc);

        console2.log("block.timestamp", block.timestamp);
        console2.log("block.number", block.number);

        AddrLib.init();
    }

    function _chainAlias() internal view returns (string memory) {
        return ChainsLib.chainAlias();
    }

    function test_vaultDeployer_factories() public {
        string memory chainAlias = _chainAlias();
        SiloVaultDeployer vaultDeployer = SiloVaultDeployer(
            payable(SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER, chainAlias))
        );

        console2.log("vaultDeployer", address(vaultDeployer));

        assertEq(
            address(vaultDeployer.SILO_INCENTIVES_CONTROLLER_FACTORY()),
            SiloCoreDeployments.get(SiloCoreContracts.INCENTIVES_CONTROLLER_FACTORY, chainAlias),
            "SILO_INCENTIVES_CONTROLLER_FACTORY"
        );

        assertEq(
            address(vaultDeployer.SILO_INCENTIVES_CONTROLLER_CL_FACTORY()),
            SiloVaultsDeployments.get(SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY, chainAlias),
            "SILO_INCENTIVES_CONTROLLER_CL_FACTORY"
        );

        assertEq(
            address(vaultDeployer.IDLE_VAULTS_FACTORY()),
            SiloVaultsDeployments.get(SiloVaultsContracts.IDLE_VAULTS_FACTORY, chainAlias),
            "IDLE_VAULTS_FACTORY"
        );
    }
}
