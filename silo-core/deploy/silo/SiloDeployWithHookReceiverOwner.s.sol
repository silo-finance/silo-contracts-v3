// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloDeploy, ISiloDeployer} from "./SiloDeploy.s.sol";

/*
FOUNDRY_PROFILE=core CONFIG=Silo_savUSD_USDC_v4 HOOK_RECEIVER_OWNER=DAO \
    forge script silo-core/deploy/silo/SiloDeployWithHookReceiverOwner.s.sol \
    --ffi --rpc-url $RPC_AVALANCHE --broadcast --verify

Resume verification:
    FOUNDRY_PROFILE=core CONFIG=Silo_savUSD_USDC_v4 HOOK_RECEIVER_OWNER=DAO \
    forge script silo-core/deploy/silo/SiloDeployWithHookReceiverOwner.s.sol \
        --ffi --rpc-url $RPC_SONIC \
        --verify \
        --private-key $PRIVATE_KEY \
        --resume
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
