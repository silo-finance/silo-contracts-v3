// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IShareToken} from "./IShareToken.sol";

interface IPermissionedLiquidationIncentiveControllerFactory {
    event PermissionedLiquidationIncentiveControllerCreated(
        address indexed controller,
        address indexed collateralShareToken
    );

    /// @notice Creates a new upgradeable PermissionedLiquidationIncentiveController proxy.
    /// @param _shareToken silo share token address
    /// @param _liquidationEnabled If true, the permissioned liquidation feature will be enabled,
    /// it can be enabled only when the share token is collateral or protected.
    /// @return controller Address of the newly created proxy.
    function create(IShareToken _shareToken, bool _liquidationEnabled) external returns (address controller);

    /// @notice Checks if a given address is a SiloIncentivesControllerCompatible.
    /// @param _controller The address to check.
    /// @return True if the address is a SiloIncentivesControllerCompatible, false otherwise.
    function isSiloIncentivesController(address _controller) external view returns (bool);
}
