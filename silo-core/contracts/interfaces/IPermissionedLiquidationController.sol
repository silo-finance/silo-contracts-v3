// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

interface IPermissionedLiquidationController {
    error LiquidationNotAllowed();
    error STokenNotSupported();
    error InvalidHookReceiver();
    error NotCollateralShareToken();
    error NotCollateralSilo();

    function setEnabled(bool _enabled) external;

    function allowMeToLiquidate() external;

    function liquidationCall(
        address _collateralAsset,
        address _debtAsset,
        address _borrower,
        uint256 _maxDebtToCover,
        bool _receiveSToken
    ) external returns (uint256 withdrawCollateral, uint256 repayDebtAssets);

    function HOOK_RECEIVER() external view returns (address); // solhint-disable-line func-name-mixedcase

    function DEBT_ASSET() external view returns (IERC20); // solhint-disable-line func-name-mixedcase

    function DEBT_SILO() external view returns (address); // solhint-disable-line func-name-mixedcase

    function COLLATERAL_ASSET() external view returns (IERC20); // solhint-disable-line func-name-mixedcase

    function enabled() external view returns (bool);
}