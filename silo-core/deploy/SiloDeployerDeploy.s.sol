// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {IInterestRateModelV2Factory} from "silo-core/contracts/interfaces/IInterestRateModelV2Factory.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";

import {SiloImplementationDeploy} from "./SiloImplementationDeploy.s.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloDeployerDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloDeployerDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume

    FOUNDRY_PROFILE=core forge verify-contract 0xe9E4f53DFF2e28272C87767aA235286134B09283 \
         silo-core/contracts/SiloDeployer.sol:SiloDeployer \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    Lib verification:

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/Actions.sol:Actions \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/ShareCollateralTokenLib.sol:ShareCollateralTokenLib \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/ShareTokenLib.sol:ShareTokenLib \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/SiloLendingLib.sol:SiloLendingLib \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/Views.sol:Views \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch
 */
contract SiloDeployerDeploy is CommonDeploy {
    function run() public returns (ISiloDeployer siloDeployer) {
        string memory chainAlias = ChainsLib.chainAlias();
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        console2.log("[SiloDeployerDeploy] chainAlias", chainAlias);

        address siloFactory = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, chainAlias);

        require(siloFactory != address(0), string.concat(SiloCoreContracts.SILO_FACTORY, " not deployed"));
        console2.log("siloFactory", siloFactory);

        if (keccak256(abi.encodePacked(chainAlias)) == keccak256(abi.encodePacked(ChainsLib.ANVIL_ALIAS))) {
            new SiloImplementationDeploy().run();
        }

        address irmConfigFactory =
            SiloCoreDeployments.get(SiloCoreContracts.INTEREST_RATE_MODEL_V2_FACTORY, chainAlias);

        require(
            irmConfigFactory != address(0),
            string.concat(SiloCoreContracts.INTEREST_RATE_MODEL_V2_FACTORY, " not deployed")
        );

        console2.log("irmConfigFactory", irmConfigFactory);

        address dkinkIRMConfigFactory =
            SiloCoreDeployments.get(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY, chainAlias);

        require(
            dkinkIRMConfigFactory != address(0),
            string.concat(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY, " not deployed")
        );

        console2.log("dkinkIRMConfigFactory", dkinkIRMConfigFactory);

        address siloImpl = SiloCoreDeployments.get(SiloCoreContracts.SILO, chainAlias);
        require(siloImpl != address(0), string.concat(SiloCoreContracts.SILO, " not deployed"));
        console2.log("siloImpl", siloImpl);

        address shareProtectedCollateralTokenImpl =
            SiloCoreDeployments.get(SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN, chainAlias);
        require(
            shareProtectedCollateralTokenImpl != address(0),
            string.concat(SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN, " not deployed")
        );
        console2.log("shareProtectedCollateralTokenImpl", shareProtectedCollateralTokenImpl);

        address shareDebtTokenImpl = SiloCoreDeployments.get(SiloCoreContracts.SHARE_DEBT_TOKEN, chainAlias);
        require(shareDebtTokenImpl != address(0), string.concat(SiloCoreContracts.SHARE_DEBT_TOKEN, " not deployed"));
        console2.log("shareDebtTokenImpl", shareDebtTokenImpl);

        vm.startBroadcast(deployerPrivateKey);

        siloDeployer = ISiloDeployer(
            address(
                new SiloDeployer(
                    IInterestRateModelV2Factory(irmConfigFactory),
                    IDynamicKinkModelFactory(dkinkIRMConfigFactory),
                    ISiloFactory(siloFactory),
                    siloImpl,
                    shareProtectedCollateralTokenImpl,
                    shareDebtTokenImpl
                )
            )
        );

        vm.stopBroadcast();

        _registerDeployment(address(siloDeployer), SiloCoreContracts.SILO_DEPLOYER);

        console2.log("[SiloDeployerDeploy] done, siloDeployer", address(siloDeployer));
    }
}
