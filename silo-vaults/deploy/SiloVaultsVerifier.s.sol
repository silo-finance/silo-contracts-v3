// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {CommonDeploy} from "./common/CommonDeploy.sol";
import {SiloVaultsContracts} from "silo-vaults/common/SiloVaultsContracts.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {console2} from "forge-std/console2.sol";
import {SiloVaultDeployer} from "silo-vaults/contracts/SiloVaultDeployer.sol";
import {
    SiloIncentivesControllerCLDeployer
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCLDeployer.sol";

/**
FOUNDRY_PROFILE=vaults \
    forge script silo-vaults/deploy/SiloVaultsVerifier.s.sol \
    --ffi --rpc-url $RPC_SONIC
 */

contract SiloVaultsVerifier is CommonDeploy {
    string public constant SUCCESS_SYMBOL = unicode"✅";
    string public constant FAIL_SYMBOL = unicode"❌";

    /// @dev list of all vaults contracts to be deployed.
    string[] allVaultsContractsNames = [
        SiloVaultsContracts.SILO_VAULTS_FACTORY,
        SiloVaultsContracts.PUBLIC_ALLOCATOR,
        SiloVaultsContracts.IDLE_VAULTS_FACTORY,
        SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY,
        SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_DEPLOYER,
        SiloVaultsContracts.SILO_VAULT_DEPLOYER
    ];

    function run() public {
        AddrLib.init();
        uint256 errorsCounter = _verifyAllDeploymentsExist();
        errorsCounter += _verifySiloVaults();

        if (errorsCounter != 0) {
            console2.log(FAIL_SYMBOL, "Finished with", errorsCounter, "errors");
        } else {
            console2.log(SUCCESS_SYMBOL, "No errors, verification is done");
        }
    }

    /// @dev Verifiers references between SiloVaultDeployer, SiloVaultsFactory, SiloIncentivesControllerFactory,
    /// SiloclFactory, IdleVaultsFactory, SiloIncentivesControllerCLDeployer.
    /// @return errorsCounter an amount of errors in deployment setup.
    function _verifySiloVaults() internal returns (uint256 errorsCounter) {
        SiloVaultDeployer siloVaultsDeployer =
            SiloVaultDeployer(getDeployedAddress(SiloVaultsContracts.SILO_VAULT_DEPLOYER));

        address deployerVaultsFactory = address(siloVaultsDeployer.SILO_VAULTS_FACTORY());

        if (deployerVaultsFactory != getDeployedAddress(SiloVaultsContracts.SILO_VAULTS_FACTORY)) {
            errorsCounter++;
            _logError("SiloVaultDeployer.SILO_VAULTS_FACTORY is not expected", deployerVaultsFactory);
        } else {
            console2.log(SUCCESS_SYMBOL, "SiloVaultDeployer.SILO_VAULTS_FACTORY is expected", deployerVaultsFactory);
        }

        address deployerCLFactory = address(siloVaultsDeployer.SILO_INCENTIVES_CONTROLLER_CL_FACTORY());
        address clFactory = getDeployedAddress(SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY);

        if (deployerCLFactory != clFactory) {
            errorsCounter++;
            _logError("SiloVaultDeployer.SILO_INCENTIVES_CONTROLLER_CL_FACTORY is not expected", deployerCLFactory);
        } else {
            console2.log(SUCCESS_SYMBOL, "SiloVaultDeployer.SILO_INCENTIVES_CONTROLLER_CL_FACTORY is expected", deployerCLFactory);
        }

        address deployerIdleVaultsFactory = address(siloVaultsDeployer.IDLE_VAULTS_FACTORY());
        address idleVaultsFactory = getDeployedAddress(SiloVaultsContracts.IDLE_VAULTS_FACTORY);

        if (deployerIdleVaultsFactory != idleVaultsFactory) {
            errorsCounter++;
            _logError("SiloVaultDeployer.IDLE_VAULTS_FACTORY is not expected", deployerIdleVaultsFactory);
        } else {
            console2.log(SUCCESS_SYMBOL, "SiloVaultDeployer.IDLE_VAULTS_FACTORY is expected", deployerIdleVaultsFactory);
        }

        SiloIncentivesControllerCLDeployer clDeployer = SiloIncentivesControllerCLDeployer(
            getDeployedAddress(SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_DEPLOYER)
        );

        address clDeployersFactory = address(clDeployer.CL_FACTORY());

        if (clDeployersFactory != clFactory) {
            errorsCounter++;
            _logError("SiloIncentivesControllerCLDeployer.CL_FACTORY is not expected", clDeployersFactory);
        } else {
            console2.log(SUCCESS_SYMBOL, "SiloIncentivesControllerCLDeployer.CL_FACTORY is expected", clDeployersFactory);
        }
    }

    /// @dev Verifies if all deployments exist.
    function _verifyAllDeploymentsExist() internal returns (uint256 errorsCounter) {
        for (uint256 i; i < allVaultsContractsNames.length; i++) {
            address deployedContract = getDeployedAddress(allVaultsContractsNames[i]);

            if (deployedContract == address(0)) {
                errorsCounter++;
                console2.log(FAIL_SYMBOL, "Can't find deployment for", allVaultsContractsNames[i]);
            } else {
                console2.log(SUCCESS_SYMBOL, "Deployment for", allVaultsContractsNames[i], "exists");
            }
        }
    }

    function _logError(string memory _msg, address _contract) internal pure {
        console2.log(FAIL_SYMBOL, _msg, Strings.toHexString(_contract));
    }
}
