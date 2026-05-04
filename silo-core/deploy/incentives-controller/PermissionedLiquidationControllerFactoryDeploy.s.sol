// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {
    PermissionedLiquidationControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationControllerFactory.sol";
import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationControllerFactory.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationControllerFactoryDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify
 */
contract PermissionedLiquidationControllerFactoryDeploy is CommonDeploy {
    function run() public returns (IPermissionedLiquidationControllerFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        factory = new PermissionedLiquidationControllerFactory();

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloCoreContracts.PERMISSIONED_LIQUIDATION_CONTROLLER_FACTORY);
    }
}
