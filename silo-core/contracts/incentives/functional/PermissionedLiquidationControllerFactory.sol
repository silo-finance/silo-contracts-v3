// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationControllerFactory.sol";
import {
    PermissionedLiquidationController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationController.sol";
import {TransparentProxy} from "silo-core/contracts/utils/TransparentProxy.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

/// @notice Minimal factory for upgradeable PermissionedLiquidationController proxies.
contract PermissionedLiquidationControllerFactory is IPermissionedLiquidationControllerFactory {
    /// @dev Implementation used by all created proxies.
    address public immutable IMPLEMENTATION;

    constructor() {
        IMPLEMENTATION = address(new PermissionedLiquidationController());
    }

    /// @inheritdoc IPermissionedLiquidationControllerFactory
    function create(IShareToken _collateralShareToken) external returns (address controller) {
        address proxyAdminOwner = Ownable(_collateralShareToken.hookReceiver()).owner();
        bytes memory initData = abi.encodeCall(PermissionedLiquidationController.initialize, (_collateralShareToken));

        controller = address(new TransparentProxy(IMPLEMENTATION, proxyAdminOwner, initData));

        emit PermissionedLiquidationControllerCreated(controller, address(_collateralShareToken));
    }
}
