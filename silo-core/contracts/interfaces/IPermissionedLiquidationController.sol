// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";

import {ISiloIncentivesController} from "../incentives/interfaces/ISiloIncentivesController.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

interface IPermissionedLiquidationController is ISiloIncentivesController, IAccessControl, IVersioned {
    struct PermisionedData {
        /// @param anySilo one of market silo, set based on hook receiver.
        address anySilo;
        /// @param enabled if false, then permissions feature is disabled and liquidation can be done as usual
        bool enabled;
        /// @param shateTokenIsDebtToken if true, that means this controller is set for debt token.
        bool shateTokenIsDebtToken;
    }

    event EnabledChanged(bool _enabled);

    error LiquidationNotAllowed();
    error OnlyHookReceiver();
    error OnlyOwner();
    error EnabledAlreadySet();
    error PauseTokenTransferAlreadySet();
    error PauseTokenTransferActive();

    function setEnabled(bool _enabled) external;

    /// @dev it will raise the flag that allows liquidation.
    /// @notice this function can be called by approved addresses,
    /// also, liquidation method in approved contract should be protected, otherwise, this flag can be abused.
    function allowMeToLiquidate() external;

    function hookReceiver() external view returns (address);

    function owner() external view returns (address);

    function permisionedData() external view returns (PermisionedData memory);
}
