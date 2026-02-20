// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultsLittleHelper} from "../../_common/VaultsLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewMintTest
*/
contract PreviewMintTest is VaultsLittleHelper {
    uint256 constant DEPOSIT_BEFORE = 1e18 + 9876543211;

    address immutable DEPOSITOR;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
    }

    /*
    forge test -vv --ffi --mt test_previewMint_beforeInterest
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_previewMint_beforeInterest_fuzz(uint256 _shares) public {
        vm.assume(_shares > 0);

        _assertPreviewMint(_shares);
    }

    /*
    forge test -vv --ffi --mt test_previewMint_afterNoInterest_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_previewMint_afterNoInterest_fuzz(
        uint128 _depositAmount,
        uint128 _shares
    ) public {
        _previewMint_afterNoInterest(_depositAmount, _shares);
        _assertPreviewMint(_shares);
    }

    /*
    forge test -vv --ffi --mt test_previewMint_withInterest_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_previewMint_withInterest_1token_fuzz(uint128 _shares) public {
        vm.assume(_shares > 1);

        _createInterest();

        _assertPreviewMint(_shares);
    }

    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_previewMint_withInterest_2tokens_fuzz(uint128 _shares) public {
        vm.assume(_shares > 1);

        _createInterest();

        _assertPreviewMint(_shares);
    }

    function _createInterest() internal {
        uint256 assets = 1e18 + 123456789; // some not even number

        vm.startPrank(DEPOSITOR);
        _silo0().deposit(assets, DEPOSITOR);
        _silo1().deposit(assets, DEPOSITOR);
        vm.stopPrank();

        address borrower = makeAddr("Borrower");
        vm.startPrank(borrower);
        _silo0().deposit(assets, borrower);
        _silo1().borrow(assets / 10, borrower, borrower);

        vm.warp(block.timestamp + 365 days);

        _silo1().repay(_silo1().maxRepay(borrower), borrower);
        vm.stopPrank();

        _silo0().accrueInterest();
        _silo1().accrueInterest();
    }

    function _previewMint_afterNoInterest(
        uint128 _depositAmount,
        uint128 _shares
    ) internal {
        vm.assume(_depositAmount > 0);
        vm.assume(_shares > 0);

        // deposit something
        _deposit(_depositAmount, makeAddr("any"));

        vm.warp(block.timestamp + 365 days);

        _assertPreviewMint(_shares);
    }

    function _assertPreviewMint(uint256 _shares) internal {
        // we can get overflow on numbers closed to max
        vm.assume(_shares < type(uint128).max);

        uint256 previewMint = vault.previewMint(_shares);

        uint256 depositedAssets = vault.mint(_shares, DEPOSITOR);

        assertEq(previewMint, depositedAssets, "previewMint == depositedAssets, NOT fewer");

        uint256 convertToAssets = vault.convertToAssets(_shares);
        uint256 diff;

        if (previewMint > convertToAssets) {
            diff = previewMint - convertToAssets;
        } else {
            diff = convertToAssets - previewMint;
        }

        assertLe(diff, 2, "diff should be less or equal than 2");
    }
}
