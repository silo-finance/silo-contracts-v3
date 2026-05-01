// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";

import {ISiloIncentivesController} from "../incentives/interfaces/ISiloIncentivesController.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

interface IPermissionedLiquidationIncentiveController is ISiloIncentivesController, IAccessControl, IVersioned {
    error LiquidationNotAllowed();
    error OnlyHookReceiver();
    error NotCollateralSilo();
    error NotCollateralShareToken();
    error EnabledAlreadySet();

    event EnabledChanged(bool _enabled);

    /// @dev it will enable or disable the liquidation feature, 
    /// it can only be done if the shared token is a collateral or protected token.
    function setEnabled(bool _enabled) external;

    /// @dev it will raise the flag that allows liquidation.
    /// @notice this function can be called by approved addresses,
    /// also, liquidation method in approved contract should be protected, otherwise, this flag can be abused.
    function allowMeToLiquidate() external;

    function hookReceiver() external view returns (address);

    /// @dev anySilo one of market silo, set based on hook receiver.
    function anySilo() external view returns (address);

    /// @dev if false, then permissions feature is disabled and liquidation can be done as usual
    function enabled() external view returns (bool);
}
