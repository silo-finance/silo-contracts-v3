// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultsLittleHelper} from "../../_common/VaultsLittleHelper.sol";

/*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mc PreviewWithdrawTest
*/
contract PreviewWithdrawTest is VaultsLittleHelper {
    address immutable DEPOSITOR;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_noInterestNoDebt_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_previewWithdraw_noInterestNoDebt_fuzz(
        uint128 _assetsOrShares,
        bool _partial
    ) public {
        uint256 amountIn = _partial ? uint256(_assetsOrShares) * 37 / 100 : _assetsOrShares;
        vm.assume(amountIn > 1);

        _deposit(_assetsOrShares, DEPOSITOR);

        amountIn -= 1;

        uint256 preview = _getPreview(amountIn);

        _assertEqPreviewAmountEqSharesWhenNoInterest(preview, amountIn);

        _assertPreviewWithdraw(preview, amountIn);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_previewWithdraw_debt_fuzz
    same asset: we check preview on same silo
    two assets: we need to borrow on silo0 in addition
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_previewWithdraw_debt_fuzz(
        uint128 _assetsOrShares,
        bool _interest,
        bool _partial
    ) public {
        vm.assume(_assetsOrShares > 1); // can not create debt with 1 collateral

        uint128 amountToUse = _partial ? uint128(uint256(_assetsOrShares) * 37 / 100) : _assetsOrShares;

        if (_useRedeem()) {
            vm.assume(amountToUse < type(uint128).max / uint128(OFFSET_POW));
            amountToUse *= uint128(OFFSET_POW);
        }

        vm.assume(amountToUse > 0);

        uint256 assets = _useRedeem() ? _assetsOrShares * OFFSET_POW : _assetsOrShares;
        _deposit(assets, DEPOSITOR);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(amountToUse);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(preview, amountToUse);
        }

        _assertPreviewWithdraw(preview, amountToUse);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_random_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_previewWithdraw_random_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        _deposit(_assetsOrShares, DEPOSITOR);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(_assetsOrShares);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(preview, _assetsOrShares);
        }

        _assertPreviewWithdraw(preview, _assetsOrShares);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_previewWithdraw_min_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_previewWithdraw_min_fuzz(uint112 _assetsOrShares, bool _interest) public {
        if (_useRedeem()) vm.assume(_assetsOrShares >= OFFSET_POW);
        else vm.assume(_assetsOrShares > 0);

        uint256 assets = _useRedeem() ? _assetsOrShares / OFFSET_POW : _assetsOrShares;
        _deposit(assets, DEPOSITOR);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 minInput = _useRedeem() ? vault.convertToShares(1) : vault.convertToAssets(vault.convertToShares(1) + 1);
        uint256 minPreview = _getPreview(minInput);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(minPreview, minInput);
        }

        _assertPreviewWithdraw(minPreview, minInput);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_max_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 1000
    function test_previewWithdraw_max_fuzz(uint64 _assets, bool _interest) public {
        vm.assume(_assets > 0);

        _deposit(_assets, DEPOSITOR);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 maxInput = _useRedeem()
            // we can not use balance of share token, because we not sure about liquidity
            ? vault.maxRedeem(DEPOSITOR)
            : vault.maxWithdraw(DEPOSITOR);

        uint256 maxPreview = _getPreview(maxInput);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(maxPreview, maxInput);
        }

        _assertPreviewWithdraw(maxPreview, maxInput);
    }

    function _createSiloUsage() internal {
        vm.prank(DEPOSITOR);
        vault.deposit(type(uint128).max, DEPOSITOR);

        address borrower = makeAddr("Borrower");

        vm.startPrank(borrower);
        _silo0().deposit(type(uint128).max, borrower);
        _silo1().borrow(type(uint64).max, borrower, borrower);
        vm.stopPrank();
    }

    function _applyInterest() internal {
        vm.warp(block.timestamp + 200 days);
        _silo0().accrueInterest();
        _silo1().accrueInterest();
    }

    function _assertPreviewWithdraw(uint256 _preview, uint256 _assetsOrShares) internal {
        vm.assume(_preview > 0);
        vm.prank(DEPOSITOR);

        uint256 results = _useRedeem()
            ? vault.redeem(_assetsOrShares, DEPOSITOR, DEPOSITOR)
            : vault.withdraw(_assetsOrShares, DEPOSITOR, DEPOSITOR);

        assertGt(results, 0, "expect any withdraw amount > 0");

        if (_useRedeem()) assertEq(_preview, results, "preview should give us exact result, NOT more");
        else assertEq(_preview, results, "preview should give us exact result, NOT fewer");
    }

    function _getPreview(uint256 _amountToUse) internal view virtual returns (uint256 preview) {
        preview = _useRedeem()
            ? vault.previewRedeem(_amountToUse)
            : vault.previewWithdraw(_amountToUse);
    }

    function _useRedeem() internal pure virtual returns (bool) {
        return false;
    }

    function _assertEqPreviewAmountEqSharesWhenNoInterest(uint256 _preview, uint256 _amountIn) private view {
        if (_useRedeem()) assertEq(_preview, _amountIn / OFFSET_POW, "previewWithdraw == shares, when no interest");
        else assertEq(_preview, _amountIn * OFFSET_POW, "previewWithdraw == assets, when no interest");
    }
}
