// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "openzeppelin5/proxy/transparent/TransparentUpgradeableProxy.sol";

import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationControllerFactory.sol";
import {
    PermissionedLiquidationController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationController.sol";

/// @notice Minimal factory for upgradeable PermissionedLiquidationController proxies.
contract PermissionedLiquidationControllerFactory is IPermissionedLiquidationControllerFactory {
    /// @dev Implementation used by all created proxies.
    address public immutable IMPLEMENTATION;

    constructor() {
        IMPLEMENTATION = address(new PermissionedLiquidationController());
    }

    /// @inheritdoc IPermissionedLiquidationControllerFactory
    function create(address _notifier) external returns (address controller) {
        address proxyAdminOwner = Ownable(_notifier).owner();
        bytes memory initData = abi.encodeCall(PermissionedLiquidationController.initialize, (_notifier));

        controller = address(new TransparentUpgradeableProxy(IMPLEMENTATION, proxyAdminOwner, initData));

        emit PermissionedLiquidationControllerCreated(controller, _notifier, proxyAdminOwner);
    }
}
