// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";

import {Silo} from "silo-core/contracts/Silo.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";

/*
    FOUNDRY_PROFILE=core forge clean
    FOUNDRY_PROFILE=core forge build --force 

    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloImplementationDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloImplementationDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume

    Lib verification:


    FOUNDRY_PROFILE=core forge verify-contract \
        --rpc-url $RPC_INJECTIVE \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        0x682095e340505C5388f8f784D6619AF8C367823e \
        silo-core/contracts/lib/Actions.sol:Actions --watch \
        --show-standard-json-input > flatten_Actions.json

    FOUNDRY_PROFILE=core forge verify-contract \
        --rpc-url $RPC_INJECTIVE \
        --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        0xfDB04b179f43b9f9680Ee1510D5cb249bF003813 \
        silo-core/contracts/lib/ShareCollateralTokenLib.sol:ShareCollateralTokenLib --watch --show-standard-json-input

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/ShareTokenLib.sol:ShareTokenLib \
        --rpc-url $RPC_INJECTIVE \
        --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE --watch \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        

    FOUNDRY_PROFILE=core forge verify-contract <contract-address> \
         silo-core/contracts/lib/SiloLendingLib.sol:SiloLendingLib \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    FOUNDRY_PROFILE=core forge verify-contract 0x811c113599E89E56e31d7fd0cA37ADE95f70e5C4 \
         silo-core/contracts/lib/Views.sol:Views \
        --rpc-url $RPC_INJECTIVE \
        --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE --watch \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch
*/
contract SiloImplementationDeploy is CommonDeploy {
    function run() public {
        string memory chainAlias = ChainsLib.chainAlias();
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        console2.log("[SiloImplementationDeploy] chainAlias", chainAlias);

        address siloFactory = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, chainAlias);

        require(siloFactory != address(0), string.concat(SiloCoreContracts.SILO_FACTORY, " not deployed"));
        console2.log("siloFactory", siloFactory);

        console2.log("\n[SiloImplementationDeploy] deploying new SiloImplementation\n");

        vm.startBroadcast(deployerPrivateKey);
        address siloImpl = address(new Silo(ISiloFactory(siloFactory)));
        vm.stopBroadcast();
        
        console2.log("New SiloImplementation deployed", siloImpl);

        vm.startBroadcast(deployerPrivateKey);
        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        vm.stopBroadcast();

        console2.log("New ShareProtectedCollateralToken deployed", shareProtectedCollateralTokenImpl);

        vm.startBroadcast(deployerPrivateKey);
        address shareDebtTokenImpl = address(new ShareDebtToken());
        vm.stopBroadcast();

        console2.log("New ShareDebtToken deployed", shareDebtTokenImpl);

        _registerDeployment(siloImpl, SiloCoreContracts.SILO);

        _registerDeployment(shareProtectedCollateralTokenImpl, SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN);

        _registerDeployment(shareDebtTokenImpl, SiloCoreContracts.SHARE_DEBT_TOKEN);
    }
}
