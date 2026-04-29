// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IPermissionedLiquidationController {
    error LiquidationNotAllowed();
    error OnlyHookReceiver();
    error OnlyOwner();

    function setEnabled(bool _enabled) external;

    /// @dev it will raise the flag that allows liquidation.
    /// @notice this function can be called by approved addresses,
    /// also, liquidation method in approved contract should be protected, otherwise, this flag can be abused.
    function allowMeToLiquidate() external;

    function hookReceiver() external view returns (address);

    /// @dev anySilo one of market silo, set based on hook receiver.
    function anySilo() external view returns (address);

    function enabled() external view returns (bool);
}
