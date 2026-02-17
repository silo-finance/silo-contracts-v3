// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {SiloIncentivesControllerFactory} from "silo-core/contracts/incentives/SiloIncentivesControllerFactory.sol";
import {ISiloIncentivesControllerFactory} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol \
        --ffi --rpc-url $RPC_INK --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol \
        --ffi --rpc-url $RPC_INK \
        --verify \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract SiloIncentivesControllerFactoryDeploy is CommonDeploy {
    function run() public returns (ISiloIncentivesControllerFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        factory = new SiloIncentivesControllerFactory();

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloCoreContracts.INCENTIVES_CONTROLLER_FACTORY);
    }
}
