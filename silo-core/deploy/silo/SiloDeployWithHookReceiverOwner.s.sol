// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloDeploy, ISiloDeployer} from "./SiloDeploy.s.sol";

/*
FOUNDRY_PROFILE=core CONFIG=Test_Silo_wXDC_USDC HOOK_RECEIVER_OWNER=DAO \
    forge script silo-core/deploy/silo/SiloDeployWithHookReceiverOwner.s.sol \
    --ffi --rpc-url $RPC_XDC_APOTHEM --broadcast --verify

Resume verification:
    FOUNDRY_PROFILE=core CONFIG=Silo_WAVAX_USDC HOOK_RECEIVER_OWNER=DAO \
    forge script silo-core/deploy/silo/SiloDeployWithHookReceiverOwner.s.sol \
        --ffi --rpc-url $RPC_SONIC \
        --verify \
        --private-key $PRIVATE_KEY \
        --resume

 */
contract SiloDeployWithHookReceiverOwner is SiloDeploy {
    function _getClonableHookReceiverConfig(address _implementation)
        internal
        override
        returns (ISiloDeployer.ClonableHookReceiver memory hookReceiver)
    {
        string memory hookReceiverOwnerKey = vm.envString("HOOK_RECEIVER_OWNER");

        address hookReceiverOwner = AddrLib.getAddress(hookReceiverOwnerKey);

        hookReceiver = ISiloDeployer.ClonableHookReceiver({
            implementation: _implementation,
            initializationData: abi.encode(hookReceiverOwner)
        });
    }

    function _getDKinkIRMInitialOwner() internal override returns (address owner) {
        string memory hookReceiverOwnerKey = vm.envString("HOOK_RECEIVER_OWNER");
        owner = AddrLib.getAddress(hookReceiverOwnerKey);
    }
}

