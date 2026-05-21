// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {IPool} from "aave-v3-origin/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/interfaces/IPoolAddressesProvider.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-origin/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {RescueTokens} from "../RescueTokens.sol";

/// @title wrapper for AAVE flashloan with IERC3156FlashLender interface
contract AaveFlashloan is IERC3156FlashLender, IFlashLoanSimpleReceiver, IVersioned, RescueTokens {
    using SafeERC20 for IERC20;

    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    IPoolAddressesProvider internal immutable _AAVE_POOL_ADDRESSES_PROVIDER;

    error InvalidProvider();
    error EmptyAdressProvider();

    constructor(IPoolAddressesProvider _poolAddressesProvider) {
        require(address(_poolAddressesProvider) != address(0), EmptyAdressProvider());
        require(_poolAddressesProvider.getPool() != address(0), InvalidProvider());

        _AAVE_POOL_ADDRESSES_PROVIDER = _poolAddressesProvider;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _data)
        external
        virtual
        returns (bool success)
    {
        bytes memory params = abi.encode(msg.sender, _receiver, _token, _data);

        IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool())
            .flashLoanSimple({
                receiverAddress: address(this), 
                asset: _token, 
                amount: _amount, 
                params: params, 
                referralCode: 0
            });

        success = true;
        emit ISilo.FlashLoan(_amount);
    }

    function executeOperation(
        address _asset,
        uint256 _amount,
        uint256 _premium,
        address,
        /* _initiator */
        bytes calldata _params
    ) external virtual returns (bool) {
        address pool = _AAVE_POOL_ADDRESSES_PROVIDER.getPool();
        require(msg.sender == pool, ISilo.FlashloanFailed());

        (address flashLoanInitiator, IERC3156FlashBorrower receiver, address token, bytes memory data) =
            abi.decode(_params, (address, IERC3156FlashBorrower, address, bytes));

        require(_asset == token, ISilo.UnsupportedFlashloanToken());

        IERC20(token).safeTransfer({to: address(receiver), value: _amount});

        require(
            receiver.onFlashLoan({
                _initiator: flashLoanInitiator, 
                _token: token, 
                _amount: _amount, 
                _fee: _premium, 
                _data: data
            }) == _FLASHLOAN_CALLBACK,
            ISilo.FlashloanFailed()
        );

        IERC20(token).safeTransferFrom({from: address(receiver), to: address(this), value: _amount + _premium});

        IERC20(token).forceApprove({spender: pool, value: _amount + _premium});

        return true;
    }

    // solhint-disable-next-line func-name-mixedcase    
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return _AAVE_POOL_ADDRESSES_PROVIDER;
    }

    // solhint-disable-next-line func-name-mixedcase    
    function POOL() external view returns (IPool) {
        return IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool());
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address _token) external view virtual override returns (uint256 maxLoan) {
        IPool pool = IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool());

        try pool.getReserveAToken(_token) returns (address aToken) {
            if (aToken == address(0)) return 0;

            maxLoan = IERC20(_token).balanceOf(aToken);
        } catch {
            maxLoan = 0;
        }
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address _token, uint256 _amount) external view virtual returns (uint256 fee) {
        IPool pool = IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool());
        address aToken = pool.getReserveAToken(_token);
        require(aToken != address(0), ISilo.UnsupportedFlashloanToken());

        fee = Math.mulDiv({
            x: pool.FLASHLOAN_PREMIUM_TOTAL(), 
            y: _amount, 
            denominator: 10000, 
            rounding: Math.Rounding.Ceil
        });
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual returns (string memory) {
        return "AaveFlashloan 4.20.1";
    }
}
