// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SiloDeploy, ISiloDeployer} from "./SiloDeploy.s.sol";

/*
FOUNDRY_PROFILE=core CONFIG=solvBTC.BBN_solvBTC \
    forge script silo-core/deploy/silo/SiloDeployWithDeployerOwner.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast --verify
 */
contract SiloDeployWithDeployerOwner is SiloDeploy {
    function _getClonableHookReceiverOwner() internal view override returns (address owner) {
        owner = _resolveOwner();
    }

    function _getDKinkIRMInitialOwner() internal view override returns (address owner) {
        owner = _resolveOwner();
    }

    function _resolveOwner() private view returns (address owner) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        owner = vm.addr(deployerPrivateKey);
    }
}
