// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Address} from "openzeppelin5/utils/Address.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "../interfaces/ISilo.sol";
import {ISiloRouterV2Implementation} from "../interfaces/ISiloRouterV2Implementation.sol";
import {IWrappedNativeToken} from "../interfaces/IWrappedNativeToken.sol";
import {IPendleWrapperLike} from "../interfaces/IPendleWrapperLike.sol";

// solhint-disable ordering

/**
Supporting the following scenarios:

## deposit
- deposit token using SiloRouterV2.multicall
    SiloRouterV2.transferFrom(IERC20 _token, address _to, uint256 _amount)
    SiloRouterV2.approve(IERC20 _token, address _spender, uint256 _amount)
    SiloRouterV2.deposit(ISilo _silo, uint256 _amount)
- deposit native & wrap in a single tx using SiloRouterV2.multicall
    SiloRouterV2.wrap(IWrappedNativeToken _native, uint256 _amount)
    SiloRouterV2.approve(IERC20 _token, address _spender, uint256 _amount)
    SiloRouterV2.deposit(ISilo _silo, uint256 _amount)

## borrow
- borrow token Silo.borrow
    SiloRouterV2.borrow(ISilo _silo, uint256 _assets, address _receiver)
- borrow wrapped native token and unwrap in a single tx using SiloRouterV2.multicall
    SiloRouterV2.borrow(ISilo _silo, uint256 _assets, address _receiver)
    SiloRouterV2.unwrap(IWrappedNativeToken _native, uint256 _amount)
    SiloRouterV2.sendValue(address payable _to, uint256 _amount)

## withdraw
- withdraw token using Silo.withdraw
    SiloRouterV2.withdraw(ISilo _silo, uint256 _amount, address _receiver, ISilo.CollateralType _collateral)
- withdraw wrapped native token and unwrap in a single tx using SiloRouterV2.multicall
    SiloRouterV2.withdraw(ISilo _silo, uint256 _amount, address _receiver, ISilo.CollateralType _collateral)
    SiloRouterV2.unwrap(IWrappedNativeToken _native, uint256 _amount)
    SiloRouterV2.sendValue(address payable _to, uint256 _amount)
- full withdraw token using Silo.redeem
    SiloRouterV2.withdrawAll(ISilo _silo, address _receiver, ISilo.CollateralType _collateral)
- full withdraw wrapped native token and unwrap in a single tx using SiloRouterV2.multicall
    SiloRouterV2.withdrawAll(ISilo _silo, address _receiver, ISilo.CollateralType _collateral)
    SiloRouterV2.unwrapAll(IWrappedNativeToken _native)
    SiloRouterV2.sendValueAll(address payable _to)

## repay
- repay token using SiloRouterV2.multicall
    SiloRouterV2.transferFrom(IERC20 _token, address _to, uint256 _amount)
    SiloRouterV2.approve(IERC20 _token, address _spender, uint256 _amount)
    SiloRouterV2.repay(ISilo _silo, uint256 _assets, address _borrower)
- repay native & wrap in a single tx using SiloRouterV2.multicall
    SiloRouterV2.wrap(IWrappedNativeToken _native, uint256 _amount)
    SiloRouterV2.approve(IERC20 _token, address _spender, uint256 _amount)
    SiloRouterV2.repay(ISilo _silo, uint256 _assets, address _borrower)
- full repay token using SiloRouterV2.multicall
    SiloRouterV2.repayAll(ISilo _silo, address _borrower)
    SiloRouterV2.transferAll(IERC20 _token, address _to)
- full repay & unwrap in a single tx using SiloRouterV2.multicall
    SiloRouterV2.repayAll(ISilo _silo, address _borrower)
    SiloRouterV2.unwrapAll(IWrappedNativeToken _native)
    SiloRouterV2.sendValueAll(address payable _to)
- full repay native
    SiloRouterV2.repayAllNative(IWrappedNativeToken _native, ISilo _silo)
    SiloRouterV2.transferAll(IERC20 _token, address _to)

## Pendle LP tokens
- wrap pendle LP token
    SiloRouterV2.wrapPendleLP(IPendleWrapperLike _wrapper, IERC20 _pendleLPToken, address _receiver, uint256 _amount)
- unwrap pendle LP token
    SiloRouterV2.unwrapPendleLP(IPendleWrapperLike _wrapper, address _receiver, uint256 _amount)
- unwrap all tokens that are on the router's balance
    SiloRouterV2.unwrapAllPendleLP(IPendleWrapperLike _wrapper, address _receiver)
 */

/// @dev This contract should never use `msg.value` as `SiloRouterV2` contract executes multicall with a delegatecall.
/// @dev This contract should not work with storage. If needed, update SiloRouterV2 accordingly.
/// @dev Caller should ensure that the router balance is empty after multicall.
contract SiloRouterV2Implementation is ISiloRouterV2Implementation {
    using SafeERC20 for IERC20;

    /// @inheritdoc ISiloRouterV2Implementation
    function wrap(IWrappedNativeToken _native, uint256 _amount) public payable virtual {
        _native.deposit{value: _amount}();
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function unwrap(IWrappedNativeToken _native, uint256 _amount) public payable virtual {
        _native.withdraw(_amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function unwrapAll(IWrappedNativeToken _native) external payable virtual {
        uint256 balance = _native.balanceOf(address(this));
        unwrap(_native, balance);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function wrapPendleLP(
        IPendleWrapperLike _wrapper,
        IERC20 _pendleLPToken,
        address _receiver,
        uint256 _amount
    ) external virtual {
        transferFrom(_pendleLPToken, address(this), _amount);
        approve(_pendleLPToken, address(_wrapper), _amount);
        _wrapper.wrap(_receiver, _amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function unwrapPendleLP(
        IPendleWrapperLike _wrapper,
        address _receiver,
        uint256 _amount
    ) public virtual {
        _wrapper.unwrap(_receiver, _amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function unwrapAllPendleLP(IPendleWrapperLike _wrapper, address _receiver) external virtual {
        uint256 balance = IERC20(address(_wrapper)).balanceOf(address(this));
        unwrapPendleLP(_wrapper, _receiver, balance);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function sendValue(address payable _to, uint256 _amount) public payable virtual {
        Address.sendValue(_to, _amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function sendValueAll(address payable _to) external payable virtual {
        uint256 balance = address(this).balance;

        if (balance != 0) { // expect this fn to be used as a sanity check at the end of the multicall
            sendValue(_to, balance);
        }
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function transfer(IERC20 _token, address _to, uint256 _amount) public payable virtual {
        _token.safeTransfer(_to, _amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function transferAll(IERC20 _token, address _to) external payable virtual {
        uint256 balance = _token.balanceOf(address(this));

        if (balance != 0) { // expect this fn to be used as a sanity check at the end of the multicall
            transfer(_token, _to, balance);
        }
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function transferFrom(IERC20 _token, address _to, uint256 _amount) public payable virtual {
        _token.safeTransferFrom(msg.sender, _to, _amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function approve(IERC20 _token, address _spender, uint256 _amount) public payable virtual {
        _token.forceApprove(_spender, _amount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function deposit(
        ISilo _silo,
        uint256 _amount,
        ISilo.CollateralType _collateral
    ) external payable virtual returns (uint256 shares) {
        shares = _silo.deposit(_amount, msg.sender, _collateral);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function withdraw(
        ISilo _silo,
        uint256 _amount,
        address _receiver,
        ISilo.CollateralType _collateral
    ) external payable virtual returns (uint256 shares) {
        shares = _silo.withdraw(_amount, _receiver, msg.sender, _collateral);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function withdrawAll(
        ISilo _silo,
        address _receiver,
        ISilo.CollateralType _collateral
    ) external payable virtual returns (uint256 assets) {
        uint256 sharesAmount = _silo.maxRedeem(msg.sender, _collateral);
        assets = _silo.redeem(sharesAmount, _receiver, msg.sender, _collateral);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function borrow(
        ISilo _silo,
        uint256 _assets,
        address _receiver
    ) external payable virtual returns (uint256 shares) {
        shares = _silo.borrow(_assets, _receiver, msg.sender);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function borrowSameAsset(
        ISilo,
        uint256,
        address
    ) external payable virtual returns (uint256) {
        revert Deprecated();
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function repay(ISilo _silo, uint256 _assets) public payable virtual returns (uint256 shares) {
        shares = _silo.repay(_assets, msg.sender);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function repayAll(ISilo _silo) external payable virtual returns (uint256 shares) {
        uint256 repayAmount = _silo.maxRepay(msg.sender);
        IERC20 asset = IERC20(_silo.asset());

        transferFrom(asset, address(this), repayAmount);
        approve(asset, address(_silo), repayAmount);

        shares = repay(_silo, repayAmount);
    }

    /// @inheritdoc ISiloRouterV2Implementation
    function repayAllNative(
        IWrappedNativeToken _native,
        ISilo _silo
    ) external payable virtual returns (uint256 shares) {
        uint256 repayAmount = _silo.maxRepay(msg.sender);

        wrap(_native, repayAmount);
        approve(IERC20(address(_native)), address(_silo), repayAmount);

        shares = repay(_silo, repayAmount);
    }
}
