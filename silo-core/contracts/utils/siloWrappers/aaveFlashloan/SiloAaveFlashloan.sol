// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {IPool} from "aave-v3-origin/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/interfaces/IPoolAddressesProvider.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-origin/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import {Silo} from "silo-core/contracts/Silo.sol";
import {ISilo, IERC3156FlashLender} from "silo-core/contracts/interfaces/ISilo.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {ShareTokenLib} from "silo-core/contracts/lib/ShareTokenLib.sol";
import {EmptySilo} from "../EmptySilo.sol";

// Keep ERC4626 ordering
// solhint-disable ordering

/// @title Silo wrapper for AAVE flashloan
contract SiloAaveFlashloan is EmptySilo, IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    IPoolAddressesProvider public immutable _AAVE_POOL_ADDRESSES_PROVIDER;
    ISiloFactory internal immutable _factory;

    error InvalidProvider();
    error EmptyAdressProvider();
    error UnsupportedFlashloanToken();
    error FlashloanFailed();

    event FlashLoan(uint256 amount);

    constructor(ISiloFactory _siloFactory, IPoolAddressesProvider _poolAddressesProvider) {
        require(address(_poolAddressesProvider) != address(0), EmptyAdressProvider());
        require(_poolAddressesProvider.getPool() != address(0), InvalidProvider());

        _AAVE_POOL_ADDRESSES_PROVIDER = _poolAddressesProvider;
        _factory = _siloFactory;
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory) {
        return "SiloWrapperAaveFlashloan 4.20.0";
    }

    function factory() external view virtual override returns (ISiloFactory) {
        return _factory;
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return _AAVE_POOL_ADDRESSES_PROVIDER;
    }

    function POOL() external view returns (IPool) {
        return IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool());
    }

    function maxFlashLoan(address _token) external view virtual override returns (uint256 maxLoan) {
        IPool pool = IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool());

        try pool.getReserveAToken(_token) returns (address aToken) {
            if (aToken == address(0)) return 0;
            maxLoan = IERC20(_token).balanceOf(aToken);
        } catch {
            maxLoan = 0;
        }
    }

    function flashFee(address _token, uint256 _amount) external view virtual override returns (uint256 fee) {
        require(_token == ShareTokenLib.siloConfig().getAssetForSilo(address(this)), UnsupportedFlashloanToken());

        fee = Math.mulDiv({
            x: IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool()).FLASHLOAN_PREMIUM_TOTAL(),
            y: _amount,
            denominator: 10000,
            rounding: Math.Rounding.Ceil
        });
    }

    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _data)
        external
        virtual
        override
        returns (bool success)
    {
        bytes memory params = abi.encode(msg.sender, _receiver, _token, _data);

        IPool(_AAVE_POOL_ADDRESSES_PROVIDER.getPool()).flashLoanSimple({
            receiverAddress: address(this),
            asset: _token,
            amount: _amount,
            params: params,
            referralCode: 0
        });

        success = true;
        if (success) emit FlashLoan(_amount);
    }

    function executeOperation(
        address _asset, 
        uint256 _amount, 
        uint256 _premium, 
        address /* _initiator */, 
        bytes calldata _params
    )
        external
        virtual
        returns (bool)
    {
        address pool = _AAVE_POOL_ADDRESSES_PROVIDER.getPool();
        require(msg.sender == pool, FlashloanFailed());

        (
            address flashLoanInitiator,
            IERC3156FlashBorrower receiver,
            address token,
            bytes memory data
        ) = abi.decode(_params, (address, IERC3156FlashBorrower, address, bytes));

        require(_asset == token, UnsupportedFlashloanToken());

        IERC20(token).safeTransfer({to: address(receiver), value: _amount});

        require(
            receiver.onFlashLoan({
                _initiator: flashLoanInitiator,
                _token: token,
                _amount: _amount,
                _fee: _premium,
                _data: data
            }) == _FLASHLOAN_CALLBACK,
            FlashloanFailed()
        );

        IERC20(token).safeTransferFrom({
            from: address(receiver), 
            to: address(this), 
            value: _amount + _premium
        });

        IERC20(token).forceApprove({
            spender: pool, 
            value: _amount + _premium
        });

        return true;
    }
}
