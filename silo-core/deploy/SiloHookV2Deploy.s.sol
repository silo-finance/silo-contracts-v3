// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";
import {ISiloHookV2} from "silo-core/contracts/interfaces/ISiloHookV2.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloHookV2Deploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloHookV2Deploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract SiloHookV2Deploy is CommonDeploy {
    function run() public returns (ISiloHookV2 hookReceiver) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        hookReceiver = ISiloHookV2(address(new SiloHookV2()));

        vm.stopBroadcast();

        _registerDeployment(address(hookReceiver), SiloCoreContracts.SILO_HOOK_V2);
    }
}
