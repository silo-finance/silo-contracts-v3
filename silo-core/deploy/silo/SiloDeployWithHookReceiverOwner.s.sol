// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloDeploy, ISiloDeployer} from "./SiloDeploy.s.sol";

/*
FOUNDRY_PROFILE=core CONFIG=Test_Silo_WINJ_PURENOISE_KinkIRM HOOK_RECEIVER_OWNER=DAO \
    forge script silo-core/deploy/silo/SiloDeployWithHookReceiverOwner.s.sol \
    --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify \
    --verifier blockscout \
    --verifier-url $VERIFIER_URL_INJECTIVE

Resume verification:
    FOUNDRY_PROFILE=core CONFIG=Test_Silo_WINJ_PURENOISE_KinkIRM HOOK_RECEIVER_OWNER=DAO \
    forge script silo-core/deploy/silo/SiloDeployWithHookReceiverOwner.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume

Warning: We haven't found any matching bytecode for the following contracts: [0xbbe34d794d470ded50b41554f72b6c48dfe784a8, 0x0a8b652840f0413c966532b167f5fd90d1bfca3a, 0x86c0ae6c94ac2a8fb2d65794071faf1898741ea4, 0x116d4e5b2c8fb797a36f58d12ab7fed827c68450, 0xcaaa286d2605a5ad7b832e7799b96198cc8d8fac, 0xef7250992dfec5799e8f5a83251869cfa4ce2b09, 0xb87c726ac377f99e5d0f3fc73a3c00c5b4d7ef35, 0xc078fc2962abe343dd49f77ec37f668a1508207f, 0xe42ea8bd2f70c52085e01b4b2e7ec0d8fe215d5f].
 */
contract SiloDeployWithHookReceiverOwner is SiloDeploy {
    function _getClonableHookReceiverOwner() internal view override returns (address owner) {
        owner = _getHookReceiverOwner()
    }

    function _getDKinkIRMInitialOwner() internal override returns (address owner) {
        owner = _getHookReceiverOwner()
    }
    
    function _getHookReceiverOwner() private view returns (address owner) {
        string memory hookReceiverOwnerKey = vm.envString("HOOK_RECEIVER_OWNER");
        owner = AddrLib.getAddress(hookReceiverOwnerKey);
    }
}
