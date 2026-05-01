// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {
    PermissionedLiquidationIncentiveControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationIncentiveControllerFactory.sol";
import {
    IPermissionedLiquidationIncentiveControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationIncentiveControllerFactory.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationIncentiveControllerFactoryDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify
 */
contract PermissionedLiquidationIncentiveControllerFactoryDeploy is CommonDeploy {
    function run() public returns (IPermissionedLiquidationIncentiveControllerFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        factory = new PermissionedLiquidationIncentiveControllerFactory();

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloCoreContracts.PERMISSIONED_LIQUIDATION_INCENTIVE_CONTROLLER_FACTORY);
    }
}
