// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";

/// @title Empty implementation of Silo ABI
contract EmptySilo {
    error NotSupported();
    
    ISiloFactory public factory;

    function DOMAIN_SEPARATOR() external pure returns (bytes32)
    {
        return bytes32(0);
    }

    function VERSION() external pure virtual returns (string memory)
    {
        return "";
    }

    function accrueInterest() external returns (uint256)
    {
        revert NotSupported();
    }

    function accrueInterestForConfig(address, uint256, uint256) external
    {
        revert NotSupported();
    }

    function allowance(address, address) external pure returns (uint256)
    {
        return 0;
    }

    function approve(address, uint256) external returns (bool)
    {
        revert NotSupported();
    }

    function asset() external pure returns (address)
    {
        return address(0);
    }

    function balanceOf(address) external pure returns (uint256)
    {
        return 0;
    }

    function balanceOfAndTotalSupply(address) external pure returns (uint256, uint256)
    {
        return (0, 0);
    }

    function borrow(uint256, address, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function borrowSameAsset(uint256, address, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function borrowShares(uint256, address, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function burn(address, address, uint256) external
    {
        revert NotSupported();
    }

    function callOnBehalfOfSilo(address, uint256, uint8, bytes calldata) external payable returns (bool, bytes memory)
    {
        revert NotSupported();
    }

    function config() external pure returns (address)
    {
        return address(0);
    }

    function convertToAssets(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function convertToAssets(uint256, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function convertToShares(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function convertToShares(uint256, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function decimals() external pure returns (uint8)
    {
        return 0;
    }

    function decimalsOffset() external pure returns (uint256)
    {
        return 0;
    }

    function deposit(uint256, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function deposit(uint256, address, uint8) external returns (uint256)
    {
        revert NotSupported();
    }

    function eip712Domain() external pure returns (bytes1, string memory, string memory, uint256, address, bytes32, uint256[] memory)
    {
        return (bytes1(0), "", "", 0, address(0), bytes32(0), new uint256[](0));
    }

    function flashFee(address, uint256) external view virtual returns (uint256)
    {
        return 0;
    }

    function flashLoan(IERC3156FlashBorrower, address, uint256, bytes calldata) external virtual returns (bool)
    {
        revert NotSupported();
    }

    function forwardTransferFromNoChecks(address, address, uint256) external
    {
        revert NotSupported();
    }

    function getCollateralAndDebtTotalsStorage() external pure returns (uint256, uint256)
    {
        return (0, 0);
    }

    function getCollateralAndProtectedTotalsStorage() external pure returns (uint256, uint256)
    {
        return (0, 0);
    }

    function getCollateralAssets() external pure returns (uint256)
    {
        return 0;
    }

    function getDebtAssets() external pure returns (uint256)
    {
        return 0;
    }

    function getFractionsStorage() external pure returns (uint64, uint64)
    {
        return (0, 0);
    }

    function getLiquidity() external pure returns (uint256)
    {
        return 0;
    }

    function getSiloStorage() external pure returns (uint192, uint64, uint256, uint256, uint256)
    {
        return (0, 0, 0, 0, 0);
    }

    function getTotalAssetsStorage(uint8) external pure returns (uint256)
    {
        return 0;
    }

    function hookReceiver() external pure returns (address)
    {
        return address(0);
    }

    function hookSetup() external pure returns (address, uint24, uint24, uint24)
    {
        return (address(0), 0, 0, 0);
    }

    function initialize(address) external
    {
        revert NotSupported();
    }

    function isSolvent(address) external pure returns (bool)
    {
        return false;
    }

    function maxBorrow(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxBorrowSameAsset(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxBorrowShares(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxDeposit(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxFlashLoan(address) external view virtual returns (uint256)
    {
        return 0;
    }

    function maxMint(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxRedeem(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxRedeem(address, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function maxRepay(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxRepayShares(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxWithdraw(address) external pure returns (uint256)
    {
        return 0;
    }

    function maxWithdraw(address, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function mint(address, address, uint256) external
    {
        revert NotSupported();
    }

    function mint(uint256, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function mint(uint256, address, uint8) external returns (uint256)
    {
        revert NotSupported();
    }

    function name() external pure returns (string memory)
    {
        return "";
    }

    function nonces(address) external pure returns (uint256)
    {
        return 0;
    }

    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external
    {
        revert NotSupported();
    }

    function previewBorrow(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewBorrowShares(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewDeposit(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewDeposit(uint256, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function previewMint(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewMint(uint256, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function previewRedeem(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewRedeem(uint256, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function previewRepay(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewRepayShares(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewWithdraw(uint256) external pure returns (uint256)
    {
        return 0;
    }

    function previewWithdraw(uint256, uint8) external pure returns (uint256)
    {
        return 0;
    }

    function redeem(uint256, address, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function redeem(uint256, address, address, uint8) external returns (uint256)
    {
        revert NotSupported();
    }

    function repay(uint256, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function repayShares(uint256, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function silo() external pure returns (address)
    {
        return address(0);
    }

    function siloConfig() external pure returns (address)
    {
        return address(0);
    }

    function switchCollateralToThisSilo() external
    {
        revert NotSupported();
    }

    function symbol() external pure returns (string memory)
    {
        return "";
    }

    function synchronizeHooks(uint24, uint24) external
    {
        revert NotSupported();
    }

    function totalAssets() external pure returns (uint256)
    {
        return 0;
    }

    function totalSupply() external pure returns (uint256)
    {
        return 0;
    }

    function transfer(address, uint256) external returns (bool)
    {
        revert NotSupported();
    }

    function transferFrom(address, address, uint256) external returns (bool)
    {
        revert NotSupported();
    }

    function transitionCollateral(uint256, address, uint8) external returns (uint256)
    {
        revert NotSupported();
    }

    function updateHooks() external
    {
        revert NotSupported();
    }

    function utilizationData() external pure returns (uint256, uint256, uint64)
    {
        return (0, 0, 0);
    }

    function withdraw(uint256, address, address) external returns (uint256)
    {
        revert NotSupported();
    }

    function withdraw(uint256, address, address, uint8) external returns (uint256)
    {
        revert NotSupported();
    }

    function withdrawFees() external
    {
        revert NotSupported();
    }

}
