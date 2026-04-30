// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IShareToken} from "./IShareToken.sol";

interface IPermissionedLiquidationControllerFactory {
    event PermissionedLiquidationControllerCreated(
        address indexed controller,
        address indexed collateralShareToken
    );

    /// @notice Creates a new upgradeable PermissionedLiquidationController proxy.
    /// @param _collateralShareToken Collateral or protected share token address
    /// @return controller Address of the newly created proxy.
    function create(IShareToken _collateralShareToken) external returns (address controller);
}
