// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SiloVaultsFactoryDeploy} from "./SiloVaultsFactoryDeploy.s.sol";
import {PublicAllocatorDeploy} from "./PublicAllocatorDeploy.s.sol";
import {IdleVaultsFactoryDeploy} from "./IdleVaultsFactoryDeploy.s.sol";
import {SiloIncentivesControllerCLFactoryDeploy} from "./SiloIncentivesControllerCLFactoryDeploy.s.sol";
import {SiloVaultsDeployerDeploy} from "./SiloVaultsDeployerDeploy.s.sol";
import {SiloIncentivesControllerCLDeployerDeploy} from "./SiloIncentivesControllerCLDeployerDeploy.s.sol";

import {SiloVaultsVerifier} from "./SiloVaultsVerifier.s.sol";

/**
    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/VaultsMainnetDeploy.s.sol:VaultsMainnetDeploy \
        --ffi --rpc-url $RPC_XDC --broadcast --verify --slow --legacy

    Resume verification:
    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/VaultsMainnetDeploy.s.sol:VaultsMainnetDeploy \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --private-key $PRIVATE_KEY \
        --resume

    XDC chain verification:

    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/VaultsMainnetDeploy.s.sol:VaultsMainnetDeploy \
        --verifier-url $VERIFIER_URL_XDC \
        --verifier custom \
        --chain 50 \
        --ffi --rpc-url $RPC_XDC \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --verify \
        --private-key $PRIVATE_KEY \
        --legacy \
        --resume
 */
contract VaultsMainnetDeploy {
    function run() public {
        SiloVaultsFactoryDeploy siloVaultsFactoryDeploy = new SiloVaultsFactoryDeploy();
        PublicAllocatorDeploy publicAllocatorDeploy = new PublicAllocatorDeploy();
        IdleVaultsFactoryDeploy idleVaultsFactoryDeploy = new IdleVaultsFactoryDeploy();
        SiloVaultsDeployerDeploy siloVaultsDeployerDeploy = new SiloVaultsDeployerDeploy();
        SiloIncentivesControllerCLDeployerDeploy siloIncentivesControllerCLDeployerDeploy =
            new SiloIncentivesControllerCLDeployerDeploy();

        SiloIncentivesControllerCLFactoryDeploy siloIncentivesControllerCLFactoryDeploy =
            new SiloIncentivesControllerCLFactoryDeploy();

        siloVaultsFactoryDeploy.run();
        publicAllocatorDeploy.run();
        idleVaultsFactoryDeploy.run();
        siloIncentivesControllerCLFactoryDeploy.run();
        siloVaultsDeployerDeploy.run();
        siloIncentivesControllerCLDeployerDeploy.run();

        // ----
        
        SiloVaultsVerifier siloVaultsVerifier = new SiloVaultsVerifier();
        siloVaultsVerifier.run();
    }
}
