// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "./ISilo.sol";
import {IWrappedNativeToken} from "./IWrappedNativeToken.sol";
import {IPendleWrapperLike} from "./IPendleWrapperLike.sol";

interface ISiloRouterV2Implementation {
    error Deprecated();
    
    /// @notice Wrap native token to wrapped native token
    /// @dev Tokens are wrapped to the router's balance.
    /// Caller is responsible to transfer the wrapped tokens to the desired address.
    /// @param _native The address of the native token
    /// @param _amount The amount of native token to wrap
    function wrap(IWrappedNativeToken _native, uint256 _amount) external payable;

    /// @notice Unwrap wrapped native token to native token
    /// @dev Tokens are unwrapped to the router's balance.
    /// Caller is responsible to transfer the unwrapped tokens to the desired address.
    /// @param _native The address of the native token
    /// @param _amount The amount of wrapped native token to unwrap
    function unwrap(IWrappedNativeToken _native, uint256 _amount) external payable;

    /// @notice Wrap pendle LP token to wrapped pendle LP token
    /// @dev Pendle LP tokens needs to be approved to the router before wrapping
    /// @param _wrapper The address of the pendle wrapper
    /// @param _pendleLPToken The address of the pendle LP token
    /// @param _amount The amount of pendle LP token to wrap
    function wrapPendleLP(
        IPendleWrapperLike _wrapper,
        IERC20 _pendleLPToken,
        address _receiver,
        uint256 _amount
    ) external;

    /// @notice Unwrap wrapped pendle LP token to pendle LP token
    /// @param _wrapper The address of the pendle wrapper
    /// @param _receiver The address of the receiver
    /// @param _amount The amount of wrapped pendle LP token to unwrap
    function unwrapPendleLP(
        IPendleWrapperLike _wrapper,
        address _receiver,
        uint256 _amount
    ) external;

    /// @notice Unwrap all wrapped pendle LP token to pendle LP token
    /// @dev By "all" it means all tokens on the router's balance
    /// @param _wrapper The address of the pendle wrapper
    /// @param _receiver The address of the receiver
    function unwrapAllPendleLP(IPendleWrapperLike _wrapper, address _receiver) external;

    /// @notice Unwrap all wrapped native token to native token
    /// @dev Tokens are unwrapped to the router's balance.
    /// Caller is responsible to transfer the unwrapped tokens to the desired address.
    /// @param _native The address of the native token
    function unwrapAll(IWrappedNativeToken _native) external payable;

    /// @notice Transfer native token from the router to an address
    /// @param _to The address to transfer the native token to
    /// @param _amount The amount of native token to transfer
    function sendValue(address payable _to, uint256 _amount) external payable;

    /// @notice Transfer all native token from the router to an address. This action must be the last one in a sequence
    /// of actions to ensure the absence of any left-overs. UI must automatically append this action if the native
    /// token is used during interaction with silo.
    /// @param _to The address to transfer the native token to
    function sendValueAll(address payable _to) external payable;

    /// @notice Transfer tokens
    /// @dev Anyone can transfer any token on behalf of the router.
    /// The caller is responsible for ensuring that the operation will not leave any leftovers on the router's balance.
    /// @param _token The address of the token
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    function transfer(IERC20 _token, address _to, uint256 _amount) external payable;

    /// @notice Transfer all tokens. This action must be the last one in a sequence of actions to ensure the absence
    /// of any left-overs. UI must automatically append this action for all assets used during interaction with silo.
    /// @dev Anyone can transfer any token on behalf of the router.
    /// @param _token The address of the token
    /// @param _to The address of the recipient
    function transferAll(IERC20 _token, address _to) external payable;

    /// @notice Transfer tokens from one address to another
    /// @param _token The address of the token
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    function transferFrom(IERC20 _token, address _to, uint256 _amount) external payable;

    /// @notice Approve tokens for a specific spender
    /// @dev Anyone can approve any token on behalf of the router.
    /// @param _token The address of the token
    /// @param _spender The address of the spender
    /// @param _amount The amount of tokens to approve
    function approve(IERC20 _token, address _spender, uint256 _amount) external payable;

    /// @notice Deposit tokens into a silo
    /// @param _silo The address of the silo
    /// @param _amount The amount of tokens to deposit
    /// @param _collateral The collateral type
    function deposit(
        ISilo _silo,
        uint256 _amount,
        ISilo.CollateralType _collateral
    ) external payable returns (uint256 shares);

    /// @notice Withdraw tokens from a silo
    /// @param _silo The address of the silo
    /// @param _amount The amount of tokens to withdraw
    /// @param _receiver The address of the receiver
    /// @param _collateral The address of the collateral token
    function withdraw(
        ISilo _silo,
        uint256 _amount,
        address _receiver,
        ISilo.CollateralType _collateral
    ) external payable returns (uint256 assets);

    /// @notice Withdraw all tokens from a silo
    /// @param _silo The address of the silo
    /// @param _receiver The address of the receiver
    /// @param _collateral The address of the collateral token
    function withdrawAll(
        ISilo _silo,
        address _receiver,
        ISilo.CollateralType _collateral
    ) external payable returns (uint256 assets);

    /// @notice Borrow tokens from a silo
    /// @param _silo The address of the silo
    /// @param _assets The amount of tokens to borrow
    /// @param _receiver The address of the receiver
    function borrow(ISilo _silo, uint256 _assets, address _receiver) external payable returns (uint256 shares);

    /// @notice deprecated
    function borrowSameAsset(
        ISilo _silo,
        uint256 _assets,
        address _receiver
    ) external payable returns (uint256 shares);

    /// @notice Repay debt
    /// @param _silo The address of the silo
    /// @param _assets The amount of tokens to repay
    function repay(ISilo _silo, uint256 _assets) external payable returns (uint256 shares);

    /// @notice Repay all debt
    /// @param _silo The address of the silo
    function repayAll(ISilo _silo) external payable returns (uint256 shares);

    /// @notice Repay all debt using native token
    /// @param _native The address of the native token
    /// @param _silo The address of the silo
    function repayAllNative(IWrappedNativeToken _native, ISilo _silo) external payable returns (uint256 shares);
}
