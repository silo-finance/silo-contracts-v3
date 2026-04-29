// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IPermissionedLiquidationControllerFactory {
    event PermissionedLiquidationControllerCreated(
        address indexed controller,
        address indexed notifier,
        address indexed proxyAdminOwner
    );

    /// @notice Creates a new upgradeable PermissionedLiquidationController proxy.
    /// @param _notifier Hook address used by the controller.
    /// @return controller Address of the newly created proxy.
    function create(address _notifier) external returns (address controller);
}
