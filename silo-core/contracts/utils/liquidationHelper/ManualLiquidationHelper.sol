// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Address} from "openzeppelin5/utils/Address.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {IPartialLiquidation} from "../../interfaces/IPartialLiquidation.sol";
import {IShareToken} from "../../interfaces/IShareToken.sol";

import {ISilo} from "../../interfaces/ISilo.sol";
import {ISiloConfig} from "../../interfaces/ISiloConfig.sol";
import {IWrappedNativeToken} from "../../interfaces/IWrappedNativeToken.sol";

import {TokenRescuer} from "../TokenRescuer.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {AllowMeToLiquidate} from "./common/AllowMeToLiquidate.sol";

/// @notice ManualLiquidationHelper is a utility contract that can be changed and replaced at any point.
/// It is not considered a part of Silo protocol. Use at your own risk.
contract ManualLiquidationHelper is TokenRescuer, AllowMeToLiquidate, IVersioned {
    using Address for address payable;
    using SafeERC20 for IERC20;

    /// @dev token receiver will get all rewards from liquidation, does not matter who will execute tx
    address payable public immutable TOKENS_RECEIVER;

    /// @dev address of wrapped native blockchain token eg. WETH on Ethereum
    address public immutable NATIVE_TOKEN;

    error MaxDebtToCoverZero();
    error UserSolvent();

    /// @param _nativeToken address of wrapped native blockchain token eg. WETH on Ethereum
    /// @param _tokensReceiver all leftover tokens (debt and collateral) will be send to this address after liquidation
    constructor (
        address _nativeToken,
        address payable _tokensReceiver
    ) {
        NATIVE_TOKEN = _nativeToken;
        TOKENS_RECEIVER = _tokensReceiver;
    }

    receive() external payable {}

    /// @dev open method to rescue tokens, tokens will be transferred to `TOKENS_RECEIVER`
    function rescueTokens(IERC20 _token) external virtual {
        _rescueTokens(TOKENS_RECEIVER, _token);
    }

    /// @dev entry point for manual liquidation
    /// @notice you need to approve ManualLiquidationHelper to be able to transfer from you tokens for repay
    /// liquidated collateral will be transfer to `TOKENS_RECEIVER`. Bad Debt is supported.
    /// @param _siloWithDebt silo address where user has debt
    /// @param _borrower user to liquidate
    function executeLiquidation(ISilo _siloWithDebt, address _borrower) external virtual {
        _executeLiquidation(_siloWithDebt, _borrower, type(uint256).max, false, TOKENS_RECEIVER);
    }

    /// @dev entry point for manual liquidation
    /// @notice you need to approve ManualLiquidationHelper to be able to transfer from you tokens for repay
    /// liquidated collateral will be transfer to `TOKENS_RECEIVER`. Bad Debt is supported.
    /// @param _siloWithDebt silo address where user has debt
    /// @param _borrower user to liquidate
    /// @param _maxDebtToCover maximum amount of debt you want to repay
    /// @param _receiveSToken if TRUE, collateral will be send as sToken
    function executeLiquidation(ISilo _siloWithDebt, address _borrower, uint256 _maxDebtToCover, bool _receiveSToken)
        external
        virtual
    {
        _executeLiquidation(_siloWithDebt, _borrower, _maxDebtToCover, _receiveSToken, TOKENS_RECEIVER);
    }

    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "ManualLiquidationHelper 4.16.0";
    }

    // solhint-disable-next-line function-max-lines
    function _executeLiquidation(
        ISilo _siloWithDebt,
        address _borrower,
        uint256 _maxDebtToCover,
        bool _receiveSToken,
        address payable _receiver
    )
        internal
        virtual
    {
        require(_maxDebtToCover != 0, MaxDebtToCoverZero());

        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _siloWithDebt.config().getConfigsForSolvency(_borrower);

        IPartialLiquidation liquidation = IPartialLiquidation(debtConfig.hookReceiver);
        _allowMeToLiquidate(debtConfig.hookReceiver, IShareToken(collateralConfig.collateralShareToken));
        _allowMeToLiquidate(debtConfig.hookReceiver, IShareToken(collateralConfig.protectedShareToken));

        IERC20 debtAsset = IERC20(debtConfig.token);

        (, uint256 debtToRepay,) = liquidation.maxLiquidation(_borrower);
        require(debtToRepay != 0, UserSolvent());

        debtAsset.safeTransferFrom(msg.sender, address(this), debtToRepay);

        debtAsset.forceApprove(debtConfig.hookReceiver, debtToRepay);

        liquidation.liquidationCall({
            _collateralAsset: collateralConfig.token,
            _debtAsset: debtConfig.token,
            _user: _borrower,
            _maxDebtToCover: Math.min(debtToRepay, _maxDebtToCover),
            _receiveSToken: _receiveSToken
        });

        debtAsset.forceApprove(debtConfig.hookReceiver, 0);

        if (_receiveSToken) {
            _transferToken(
                _receiver,
                collateralConfig.protectedShareToken,
                IERC20(collateralConfig.protectedShareToken).balanceOf(address(this))
            );
            _transferToken(
                _receiver,
                collateralConfig.collateralShareToken,
                IERC20(collateralConfig.collateralShareToken).balanceOf(address(this))
            );
        } else {
            _transferToken(_receiver, collateralConfig.token, IERC20(collateralConfig.token).balanceOf(address(this)));
        }
    }

    function _transferToken(address payable _receiver, address _asset, uint256 _amount) internal virtual {
        if (_amount == 0) return;

        if (_asset == NATIVE_TOKEN) {
            _transferNative(_receiver, _amount);
        } else {
            IERC20(_asset).safeTransfer(_receiver, _amount);
        }
    }

    /// @notice We assume that quoteToken is wrapped native token
    function _transferNative(address payable _receiver, uint256 _amount) internal virtual {
        IWrappedNativeToken(address(NATIVE_TOKEN)).withdraw(_amount);
        _receiver.sendValue(_amount);
    }
}
