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

// Keep ERC4626 ordering
// solhint-disable ordering

/// @title Silo wrapper for AAVE flashloan
contract EmptySilo is ISilo, IShareToken, IVersioned {
    using SafeERC20 for IERC20;

    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public factory;

    error NotSupported();
    error InvalidProvider();
    error EmptyAdressProvider();

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory) {
        return "EmptySilo 4.20.0";
    }

    /// @inheritdoc ISilo
    function callOnBehalfOfSilo(address, uint256, CallType, bytes calldata)
        external
        payable
        virtual
        override
        returns (bool, bytes memory)
    {
        revert NotSupported();
    }

    /// @inheritdoc ISilo
    function maxBorrow(address) external view virtual override returns (uint256 maxAssets) {
        maxAssets = 0;
    }

    /// @inheritdoc ISilo
    function previewBorrow(uint256) external view virtual override returns (uint256 shares) {
        shares = 0;
    }

    /// @inheritdoc ISilo
    function borrow(uint256, address, address) external virtual override returns (uint256) {
        revert NotSupported();
    }

    /// @inheritdoc ISilo
    function maxBorrowShares(address) external view virtual override returns (uint256 maxShares) {
        maxShares = 0;
    }

    /// @inheritdoc ISilo
    function previewBorrowShares(uint256) external view virtual override returns (uint256 assets) {
        assets = 0;
    }

    /// @inheritdoc ISilo
    function borrowShares(uint256, address, address) external virtual override returns (uint256) {
        revert NotSupported();
    }

    /// @inheritdoc ISilo
    function maxBorrowSameAsset(address) external pure virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc ISilo
    function transitionCollateral(uint256, address, CollateralType)
        external
        virtual
        override
        returns (uint256)
    {
        revert NotSupported();
    }
}
