// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";

/// @title Empty implementation of Silo ABI
contract EmptySilo {
    error NotSupported();

    function DOMAIN_SEPARATOR() external virtual pure returns (bytes32) {}

    function VERSION() external virtual pure virtual returns (string memory) {}

    function accrueInterest() external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function accrueInterestForConfig(address, uint256, uint256) external virtual pure {
        revert NotSupported();
    }

    function allowance(address, address) external virtual pure returns (uint256) {}

    function approve(address, uint256) external virtual pure returns (bool) {
        revert NotSupported();
    }

    function asset() external virtual pure returns (address) {}

    function balanceOf(address) external virtual pure returns (uint256) {}

    function balanceOfAndTotalSupply(address) external virtual pure returns (uint256, uint256) {}

    function borrow(uint256, address, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function borrowSameAsset(uint256, address, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function borrowShares(uint256, address, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function burn(address, address, uint256) external virtual pure {
        revert NotSupported();
    }

    function callOnBehalfOfSilo(address, uint256, uint8, bytes calldata)
        external virtual
        pure
        returns (bool, bytes memory)
    {
        revert NotSupported();
    }

    function config() external virtual pure returns (address) {}

    function convertToAssets(uint256) external virtual pure returns (uint256) {}

    function convertToAssets(uint256, uint8) external virtual pure returns (uint256) {}

    function convertToShares(uint256) external virtual pure returns (uint256) {}

    function convertToShares(uint256, uint8) external virtual pure returns (uint256) {}

    function decimals() external virtual pure returns (uint8) {}

    function decimalsOffset() external virtual pure returns (uint256) {}

    function deposit(uint256, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function deposit(uint256, address, uint8) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function eip712Domain()
        external virtual
        pure
        returns (bytes1, string memory, string memory, uint256, address, bytes32, uint256[] memory)
    {}

    function factory() external virtual view virtual returns (ISiloFactory) {}

    function flashFee(address, uint256) external virtual view virtual returns (uint256) {}

    function flashLoan(IERC3156FlashBorrower, address, uint256, bytes calldata) external virtual returns (bool) {
        revert NotSupported();
    }

    function forwardTransferFromNoChecks(address, address, uint256) external virtual pure {
        revert NotSupported();
    }

    function getCollateralAndDebtTotalsStorage() external virtual pure returns (uint256, uint256) {}

    function getCollateralAndProtectedTotalsStorage() external virtual pure returns (uint256, uint256) {}

    function getCollateralAssets() external virtual pure returns (uint256) {}

    function getDebtAssets() external virtual pure returns (uint256) {}

    function getFractionsStorage() external virtual pure returns (uint64, uint64) {}

    function getLiquidity() external virtual pure returns (uint256) {}

    function getSiloStorage() external virtual pure returns (uint192, uint64, uint256, uint256, uint256) {}

    function getTotalAssetsStorage(uint8) external virtual pure returns (uint256) {}

    function hookReceiver() external virtual pure returns (address) {}

    function hookSetup() external virtual pure returns (address, uint24, uint24, uint24) {}

    function initialize(address) external virtual pure {
        revert NotSupported();
    }

    function isSolvent(address) external virtual pure returns (bool) {}

    function maxBorrow(address) external virtual pure returns (uint256) {}

    function maxBorrowSameAsset(address) external virtual pure returns (uint256) {}

    function maxBorrowShares(address) external virtual pure returns (uint256) {}

    function maxDeposit(address) external virtual pure returns (uint256) {}

    function maxFlashLoan(address) external virtual view virtual returns (uint256) {}

    function maxMint(address) external virtual pure returns (uint256) {}

    function maxRedeem(address) external virtual pure returns (uint256) {}

    function maxRedeem(address, uint8) external virtual pure returns (uint256) {}

    function maxRepay(address) external virtual pure returns (uint256) {}

    function maxRepayShares(address) external virtual pure returns (uint256) {}

    function maxWithdraw(address) external virtual pure returns (uint256) {}

    function maxWithdraw(address, uint8) external virtual pure returns (uint256) {}

    function mint(address, address, uint256) external virtual pure {
        revert NotSupported();
    }

    function mint(uint256, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function mint(uint256, address, uint8) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function name() external virtual pure returns (string memory) {}

    function nonces(address) external virtual pure returns (uint256) {}

    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external virtual pure {
        revert NotSupported();
    }

    function previewBorrow(uint256) external virtual pure returns (uint256) {}

    function previewBorrowShares(uint256) external virtual pure returns (uint256) {}

    function previewDeposit(uint256) external virtual pure returns (uint256) {}

    function previewDeposit(uint256, uint8) external virtual pure returns (uint256) {}

    function previewMint(uint256) external virtual pure returns (uint256) {}

    function previewMint(uint256, uint8) external virtual pure returns (uint256) {}

    function previewRedeem(uint256) external virtual pure returns (uint256) {}

    function previewRedeem(uint256, uint8) external virtual pure returns (uint256) {}

    function previewRepay(uint256) external virtual pure returns (uint256) {}

    function previewRepayShares(uint256) external virtual pure returns (uint256) {}

    function previewWithdraw(uint256) external virtual pure returns (uint256) {}

    function previewWithdraw(uint256, uint8) external virtual pure returns (uint256) {}

    function redeem(uint256, address, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function redeem(uint256, address, address, uint8) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function repay(uint256, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function repayShares(uint256, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function silo() external virtual pure returns (address) {}

    function siloConfig() external virtual pure returns (address) {}

    function switchCollateralToThisSilo() external virtual pure {
        revert NotSupported();
    }

    function symbol() external virtual pure returns (string memory) {}

    function synchronizeHooks(uint24, uint24) external virtual pure {
        revert NotSupported();
    }

    function totalAssets() external virtual pure returns (uint256) {}

    function totalSupply() external virtual pure returns (uint256) {}

    function transfer(address, uint256) external virtual pure returns (bool) {
        revert NotSupported();
    }

    function transferFrom(address, address, uint256) external virtual pure returns (bool) {
        revert NotSupported();
    }

    function transitionCollateral(uint256, address, uint8) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function updateHooks() external virtual pure {
        revert NotSupported();
    }

    function utilizationData() external virtual pure returns (uint256, uint256, uint64) {}

    function withdraw(uint256, address, address) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function withdraw(uint256, address, address, uint8) external virtual pure returns (uint256) {
        revert NotSupported();
    }

    function withdrawFees() external virtual pure {
        revert NotSupported();
    }
}
