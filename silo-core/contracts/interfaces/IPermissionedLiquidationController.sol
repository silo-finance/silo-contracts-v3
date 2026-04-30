// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IPermissionedLiquidationController {
    error LiquidationNotAllowed();
    error InvalidHookReceiver();
    error NotCollateralShareToken();
    error NotCollateralSilo();
    error OnlyHookReceiver();

    function setEnabled(bool _enabled) external;

    /// @dev it will raise the flag that allows liquidation.
    /// @notice this function can be called by approved addresses,
    /// also, liquidation method in approved contract should be protected, otherwise, this flag can be abused
    function allowMeToLiquidate() external;

    function HOOK_RECEIVER() external view returns (address); // solhint-disable-line func-name-mixedcase

    function enabled() external view returns (bool);
}
