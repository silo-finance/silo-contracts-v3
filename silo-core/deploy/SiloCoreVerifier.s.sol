// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {InterestRateModelV2Factory} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";
import {InterestRateModelV2} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {console2} from "forge-std/console2.sol";

/*
FOUNDRY_PROFILE=core EXPECTED_OWNER=DAO \
    forge script silo-core/deploy/SiloCoreVerifier.s.sol \
    --ffi --rpc-url $RPC_SONIC
 */
contract SiloCoreVerifier is CommonDeploy {
    string public constant SUCCESS_SYMBOL = unicode"✅";
    string public constant FAIL_SYMBOL = unicode"❌";

    /// @dev list of all core contracts to be deployed.
    string[] allCoreContractsNames = [
        SiloCoreContracts.SILO_FACTORY,
        SiloCoreContracts.INTEREST_RATE_MODEL_V2_FACTORY,
        SiloCoreContracts.INTEREST_RATE_MODEL_V2,
        SiloCoreContracts.SILO_HOOK_V1,
        SiloCoreContracts.SILO_DEPLOYER,
        SiloCoreContracts.SILO,
        SiloCoreContracts.LIQUIDATION_HELPER,
        SiloCoreContracts.MANUAL_LIQUIDATION_HELPER,
        SiloCoreContracts.TOWER,
        SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN,
        SiloCoreContracts.SHARE_DEBT_TOKEN,
        SiloCoreContracts.SILO_LENS,
        SiloCoreContracts.SILO_ROUTER_V2,
        SiloCoreContracts.INCENTIVES_CONTROLLER_FACTORY
    ];

    /// @dev list of core contracts name to skip ownership check.
    string[] skipCheckOwnerForContractNames = [
        SiloCoreContracts.SILO_HOOK_V1, // implementation, does not have storage for owner
        SiloCoreContracts.TOWER // controlled by deployer wallet, UI utils
    ];

    function run() public {
        AddrLib.init();
        address expectedOwner = AddrLib.getAddress(vm.envString("EXPECTED_OWNER"));
        uint256 errorsCounter = _verifyOwners(expectedOwner);
        errorsCounter += _verifyLinks({_daoFeeReceiver: expectedOwner});

        if (errorsCounter != 0) {
            console2.log(FAIL_SYMBOL, "Finished with", errorsCounter, "errors");
        } else {
            console2.log(SUCCESS_SYMBOL, "No errors, verification is done");
        }
    }

    /// @dev Verifies protocol role model. All ownerships are transferred to the expected owner,
    /// fee receivers are correct, etc.
    /// @param _expectedOwner expected Ownable contracts owner.
    /// @return errorsCounter amount of errors.
    function _verifyOwners(address _expectedOwner) internal returns (uint256 errorsCounter) {
        address[] memory allCoreContracts;
        (allCoreContracts, errorsCounter) = _getAllCoreContracts();

        for (uint256 i; i < allCoreContracts.length; i++) {
            (bool success, address owner) = _tryGetOwner(allCoreContracts[i]);

            if (!_skipCheckOwnerForContractName(allCoreContractsNames[i]) && success && owner != _expectedOwner) {
                errorsCounter++;

                console2.log(FAIL_SYMBOL, allCoreContractsNames[i], "owner is not expected, real owner is", owner);
            }
        }
    }

    /// @dev Verifies "links" across deployed contracts. For example, SILO_FACTORY from
    /// SiloDeployer is equal to the latest factory deployment.
    /// @return errorsCounter amount of errors.
    function _verifyLinks(address _daoFeeReceiver) internal returns (uint256 errorsCounter) {
        SiloFactory siloFactory = SiloFactory(getDeployedAddress(SiloCoreContracts.SILO_FACTORY));
        address daoFeeReceiver = siloFactory.daoFeeReceiver();

        if (daoFeeReceiver != _daoFeeReceiver) {
            errorsCounter++;
            _logError("Fee receiver is not expected", daoFeeReceiver);
        }

        Silo silo = Silo(payable(getDeployedAddress(SiloCoreContracts.SILO)));

        if (silo.factory() != siloFactory) {
            errorsCounter++;
            _logError("Silo.factory() is not expected", address(silo.factory()));
        }

        errorsCounter += _verifySiloDeployer();
    }

    function _verifySiloDeployer() internal returns (uint256 errorsCounter) {
        SiloDeployer siloDeployer = SiloDeployer(getDeployedAddress(SiloCoreContracts.SILO_DEPLOYER));
        address siloDeployerIrmFactory = address(siloDeployer.IRM_CONFIG_FACTORY());
        address irmV2Factory = getDeployedAddress(SiloCoreContracts.INTEREST_RATE_MODEL_V2_FACTORY);
        address siloFactory = getDeployedAddress(SiloCoreContracts.SILO_FACTORY);

        if (siloDeployerIrmFactory != irmV2Factory) {
            errorsCounter++;
            _logError("SiloDeployer IRM_CONFIG_FACTORY is not expected", siloDeployerIrmFactory);
        }

        address siloDeployerSiloFactory = address(siloDeployer.SILO_FACTORY());

        if (siloDeployerSiloFactory != siloFactory) {
            errorsCounter++;
            _logError("SiloDeployer SILO_FACTORY is not expected", siloDeployerSiloFactory);
        }

        address siloDeployerSiloImpl = address(siloDeployer.SILO_IMPL());

        if (siloDeployerSiloImpl != getDeployedAddress(SiloCoreContracts.SILO)) {
            errorsCounter++;
            _logError("SiloDeployer SILO_IMPL is not expected", siloDeployerSiloImpl);
        }

        address siloDeployerProtectedTokenImpl = address(siloDeployer.SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL());

        if (siloDeployerProtectedTokenImpl != getDeployedAddress(SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN))
        {
            errorsCounter++;

            _logError(
                "SiloDeployer SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL is not expected", siloDeployerProtectedTokenImpl
            );
        }

        address siloDeployerDebtTokenImpl = address(siloDeployer.SHARE_DEBT_TOKEN_IMPL());

        if (siloDeployerDebtTokenImpl != getDeployedAddress(SiloCoreContracts.SHARE_DEBT_TOKEN)) {
            errorsCounter++;
            _logError("SiloDeployer SHARE_DEBT_TOKEN_IMPL is not expected", siloDeployerDebtTokenImpl);
        }
    }

    /// @dev Returns an array of all silo-core contracts addresses, throws if anything is not found. Index of a
    /// contract corresponds to it's name in all core contract names.
    /// @return allCoreContracts is a complete list of core contracts addresses.
    /// @return errorsCounter amount of errors.
    function _getAllCoreContracts() internal returns (address[] memory allCoreContracts, uint256 errorsCounter) {
        allCoreContracts = new address[](allCoreContractsNames.length);

        for (uint256 i; i < allCoreContractsNames.length; i++) {
            allCoreContracts[i] = getDeployedAddress(allCoreContractsNames[i]);

            if (allCoreContracts[i] == address(0)) {
                errorsCounter++;
                console2.log(FAIL_SYMBOL, "Can't find deployment for", allCoreContractsNames[i]);
            }
        }
    }

    /// @dev Checks if the contract ownership check should be skipped. For example, SiloHookReceiver implementation
    /// does not have storage for owner() but has an interface.
    /// @return skip true if check should be skipped.
    function _skipCheckOwnerForContractName(string memory _contractName) internal view returns (bool skip) {
        for (uint256 i; i < skipCheckOwnerForContractNames.length; i++) {
            if (Strings.equal(_contractName, skipCheckOwnerForContractNames[i])) {
                return true;
            }
        }

        return false;
    }

    /// @dev Tries to get an owner, returns fail if contract does not implement ownable interface.
    /// @return success true if contract is ownable.
    /// @return owner owner address if contract is ownable.
    function _tryGetOwner(address _ownableContract) internal view returns (bool success, address owner) {
        if (_ownableContract == address(0)) {
            return (false, address(0));
        }

        try Ownable(_ownableContract).owner() returns (address contractOwner) {
            success = true;
            owner = contractOwner;
        } catch {}
    }

    function _logError(string memory _msg, address _contract) internal pure {
        console2.log(FAIL_SYMBOL, _msg, _contract);
    }
}
