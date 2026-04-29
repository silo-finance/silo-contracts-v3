// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

interface IPermissionedLiquidationController {
    error LiquidationNotAllowed();
    error InvalidHookReceiver();
    error NotCollateralShareToken();
    error NotCollateralSilo();
    error OnlyHookReceiver();

    function setEnabled(bool _enabled) external;

    function allowMeToLiquidate() external;

    function HOOK_RECEIVER() external view returns (address); // solhint-disable-line func-name-mixedcase

    function enabled() external view returns (bool);
}
