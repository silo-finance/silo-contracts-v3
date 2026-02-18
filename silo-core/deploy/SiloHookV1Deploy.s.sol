// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloHookV1} from "silo-core/contracts/hooks/SiloHookV1.sol";
import {ISiloHookV1} from "silo-core/contracts/interfaces/ISiloHookV1.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloHookV1Deploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloHookV1Deploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract SiloHookV1Deploy is CommonDeploy {
    function run() public returns (ISiloHookV1 hookReceiver) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        hookReceiver = ISiloHookV1(address(new SiloHookV1()));

        vm.stopBroadcast();

        _registerDeployment(address(hookReceiver), SiloCoreContracts.SILO_HOOK_V1);
    }
}
