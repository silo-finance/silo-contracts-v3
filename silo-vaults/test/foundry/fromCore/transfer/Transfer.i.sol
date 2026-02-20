// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {VaultsLittleHelper} from "../_common/VaultsLittleHelper.sol";

/*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc TransferTest -vv
*/
contract TransferTest is VaultsLittleHelper {
    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_transferAccrueFee
    */
    function test_transferAccrueFee() public {
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");

        _createPositionsWithInterest(depositor, borrower);

        uint256 totalAssetsBefore = vault.totalAssets();
        // move time to accrue interest
        vm.warp(block.timestamp + 100 days);
        uint256 totalAssetsAfter = vault.totalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore, "totalAssets should increase");

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();

        uint256 vaultDepositorShares = vault.balanceOf(depositor);

        vm.prank(depositor);
        require(vault.transfer(borrower, vaultDepositorShares), "transfer failed");

        assertEq(vault.balanceOf(borrower), vaultDepositorShares, "borrower should have the shares");

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertGt(lastTotalAssetsAfter, lastTotalAssetsBefore, "lastTotalAssets should increase");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_transferFromAccrueFee
    */
    function test_transferFromAccrueFee() public {
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");

        _createPositionsWithInterest(depositor, borrower);

        uint256 totalAssetsBefore = vault.totalAssets();
        // move time to accrue interest
        vm.warp(block.timestamp + 100 days);
        uint256 totalAssetsAfter = vault.totalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore, "totalAssets should increase");

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();

        uint256 vaultDepositorShares = vault.balanceOf(depositor);

        vm.prank(depositor);
        vault.approve(borrower, vaultDepositorShares);

        vm.prank(borrower);
        require(vault.transferFrom(depositor, borrower, vaultDepositorShares), "transfer failed");

        assertEq(vault.balanceOf(borrower), vaultDepositorShares, "borrower should have the shares");

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertGt(lastTotalAssetsAfter, lastTotalAssetsBefore, "lastTotalAssets should increase");
    }

    function _createPositionsWithInterest(address _depositor, address _borrower) internal {
        uint256 depositAmount = 1000_000e18;
        _deposit(depositAmount, _depositor);

        ISilo market = ISilo(address(allMarkets[0]));
        ISilo collateralMarket = ISilo(address(collateralMarkets[market]));

        vm.prank(_borrower);
        collateralMarket.deposit(depositAmount, _borrower, ISilo.CollateralType.Collateral);

        vm.prank(_borrower);
        market.borrow(depositAmount / 2, _borrower, _borrower);
    }
}
