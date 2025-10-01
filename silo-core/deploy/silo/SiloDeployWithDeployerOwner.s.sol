// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SiloDeploy, ISiloDeployer} from "./SiloDeploy.s.sol";

/**
FOUNDRY_PROFILE=core CONFIG=solvBTC.BBN_solvBTC \
    forge script silo-core/deploy/silo/SiloDeployWithDeployerOwner.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast --verify

    XDC deployment:

    FOUNDRY_PROFILE=core CONFIG=Silo_wXDC_USDC \
    forge script silo-core/deploy/silo/SiloDeployWithDeployerOwner.s.sol \
    --ffi --rpc-url $RPC_XDC --broadcast --legacy
 */
contract SiloDeployWithDeployerOwner is SiloDeploy {
    function _getClonableHookReceiverConfig(address _implementation)
        internal
        view
        override
        returns (ISiloDeployer.ClonableHookReceiver memory hookReceiver)
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address owner = vm.addr(deployerPrivateKey);

        hookReceiver = ISiloDeployer.ClonableHookReceiver({
            implementation: _implementation,
            initializationData: abi.encode(owner)
        });
    }

    function _getDKinkIRMInitialOwner() internal view override returns (address owner) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        owner = vm.addr(deployerPrivateKey);
    }
}
