// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {IFlashLoanSimpleReceiver} from "aave-v3-origin/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPool} from "aave-v3-origin/interfaces/IPool.sol";

import {ISilo, IERC3156FlashLender} from "./interfaces/ISilo.sol";
import {IVersioned} from "./interfaces/IVersioned.sol";

import {IERC3156FlashBorrower} from "./interfaces/IERC3156FlashBorrower.sol";
import {ISiloFactory} from "./interfaces/ISiloFactory.sol";


// Keep ERC4626 ordering
// solhint-disable ordering

/// @title Silo vault with lending and borrowing functionality
/// @notice Silo is a ERC4626-compatible vault that allows users to deposit collateral and borrow debt. This contract
/// is deployed twice for each asset for two-asset lending markets.
/// Version: 2.0.0
contract SiloFlashloan is Silo {
    IPool public immutable POOL;
    error NotSupported();

    constructor(ISiloFactory _siloFactory) Silo(_siloFactory) {
        // POOL = IPool(IPoolAddressesProvider(ADDRESSES_PROVIDER).getPool());
        POOL = IPool(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3); // sonic
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory) {
        return "Silo 4.20.0";
    }

    /// @inheritdoc ISilo
    function callOnBehalfOfSilo(address _target, uint256 _value, CallType _callType, bytes calldata _input)
        external
        virtual
        payable
        override
        returns (bool success, bytes memory result)
    {
        revert NotSupported();
    }

    /// @inheritdoc ISilo
    function maxBorrow(address _borrower) external view virtual override returns (uint256 maxAssets) {
        maxAssets = 0;
    }

    /// @inheritdoc ISilo
    function previewBorrow(uint256 _assets) external view virtual override returns (uint256 shares) {
        shares = 0;
    }

    /// @inheritdoc ISilo
    function borrow(uint256 _assets, address _receiver, address _borrower)
        external
        virtual
        override
        returns (uint256 shares)
    {
        revert NotSupported();
    }

    /// @inheritdoc ISilo
    function maxBorrowShares(address _borrower) external view virtual override returns (uint256 maxShares) {
        maxShares = 0;
    }

    /// @inheritdoc ISilo
    function previewBorrowShares(uint256 _shares) external view virtual override returns (uint256 assets) {
        assets = 0;
    }

    /// @inheritdoc ISilo
    function borrowShares(uint256 _shares, address _receiver, address _borrower)
        external
        virtual
        override
        returns (uint256 assets)
    {
        revert NotSupported();
    }

    /// @inheritdoc ISilo
    function maxBorrowSameAsset(address) external pure virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc ISilo
    function borrowSameAsset(uint256, address, address) external virtual override returns (uint256) {
        revert Deprecated();
    }

    /// @inheritdoc ISilo
    function transitionCollateral(
        uint256 _shares,
        address _owner,
        CollateralType _transitionFrom
    )
        external
        virtual
        override
        returns (uint256 assets)
    {
        revert NotSupported();
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address _token) external view virtual override returns (uint256 maxLoan) {
        maxLoan = Views.maxFlashLoan(_token);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address _token, uint256 _amount) external view virtual override returns (uint256 fee) {
        fee = POOL.FLASHLOAN_PREMIUM_TOTAL() * _amount / 10000;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _data)
        external
        virtual
        returns (bool success)
    {
        success = Actions.flashLoan(_receiver, _token, _amount, _data);
        if (success) emit FlashLoan(_amount);
    }
}
