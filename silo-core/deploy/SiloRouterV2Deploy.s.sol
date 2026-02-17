// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloRouterV2} from "silo-core/contracts/silo-router/SiloRouterV2.sol";
import {SiloRouterV2Implementation} from "silo-core/contracts/silo-router/SiloRouterV2Implementation.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloRouterV2Deploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloRouterV2Deploy.s.sol \
        --ffi --rpc-url $RPC_INK \
        --verify \
        --verifier blockscout --verifier-url $VERIFIER_URL_INK \
        --private-key $PRIVATE_KEY \
        --resume
*/
contract SiloRouterV2Deploy is CommonDeploy {
    function run() public returns (SiloRouterV2 siloRouterV2) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        SiloRouterV2Implementation implementation = new SiloRouterV2Implementation();

        siloRouterV2 = new SiloRouterV2(deployer, address(implementation));

        vm.stopBroadcast();

        _registerDeployment(address(siloRouterV2), SiloCoreContracts.SILO_ROUTER_V2);
    }
}
