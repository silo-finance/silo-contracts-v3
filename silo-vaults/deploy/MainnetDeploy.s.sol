// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SiloVaultsFactoryDeploy} from "./SiloVaultsFactoryDeploy.s.sol";
import {PublicAllocatorDeploy} from "./PublicAllocatorDeploy.s.sol";
import {IdleVaultsFactoryDeploy} from "./IdleVaultsFactoryDeploy.s.sol";
import {SiloIncentivesControllerCLFactoryDeploy} from "./SiloIncentivesControllerCLFactoryDeploy.s.sol";
import {SiloVaultsDeployerDeploy} from "./SiloVaultsDeployerDeploy.s.sol";
import {SiloIncentivesControllerCLDeployerDeploy} from "./SiloIncentivesControllerCLDeployerDeploy.s.sol";

/**
    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/MainnetDeploy.s.sol:MainnetDeploy \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow \
        --verify --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE

    Resume verification:
    FOUNDRY_PROFILE=vaults \
        forge script silo-vaults/deploy/MainnetDeploy.s.sol:MainnetDeploy \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract MainnetDeploy {
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
    }
}
