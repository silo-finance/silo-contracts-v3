// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {Tower} from "silo-core/contracts/utils/Tower.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

/*
    FOUNDRY_PROFILE=core \
    forge script silo-core/deploy/TowerDeploy.s.sol:TowerDeploy \
    --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify


    in case verification fail, set `ETHERSCAN_API_KEY` in env and run:
    FOUNDRY_PROFILE=core \
    forge script silo-core/deploy/TowerDeploy.s.sol:TowerDeploy \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract TowerDeploy is CommonDeploy {
    function run() public returns (Tower tower) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        tower = new Tower();

        vm.stopBroadcast();

        _registerDeployment(address(tower), SiloCoreContracts.TOWER);
    }
}
