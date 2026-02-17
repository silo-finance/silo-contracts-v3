// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewWithdrawTest
*/
contract PreviewWithdrawTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;
    address immutable depositor;
    address immutable borrower;

    constructor() {
        depositor = makeAddr("Depositor");
        borrower = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_noInterestNoDebt_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewWithdraw_noInterestNoDebt_fuzz(uint128 _assetsOrShares, bool _partial) public {
        uint256 amountIn = _partial ? uint256(_assetsOrShares) * 37 / 100 : _assetsOrShares;
        vm.assume(amountIn > 0);

        _depositForTestPreview(_assetsOrShares);

        uint256 preview = _getPreview(amountIn);

        _assertEqPrevAmountInSharesWhenNoInterest(preview, amountIn);

        _assertPreviewWithdraw(preview, amountIn);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_debt_fuzz
    same asset: we check preview on same silo
    two assets: we need to borrow on silo0 in addition
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewWithdraw_debt_fuzz(uint128 _assetsOrShares, bool _interest, bool _partial) public {
        vm.assume(_assetsOrShares > 1); // can not create debt with 1 collateral
        uint128 amountToUse = _partial ? uint128(uint256(_assetsOrShares) * 37 / 100) : _assetsOrShares;
        vm.assume(amountToUse > 0);

        _depositForTestPreview(_assetsOrShares);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(amountToUse);

        if (!_interest || _collateralType() == ISilo.CollateralType.Protected) {
            _assertEqPrevAmountInSharesWhenNoInterest(preview, amountToUse);
        }

        _assertPreviewWithdraw(preview, amountToUse);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_random_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewWithdraw_random_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        _depositForTestPreview(_assetsOrShares);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(_assetsOrShares);

        if (!_interest || _collateralType() == ISilo.CollateralType.Protected) {
            _assertEqPrevAmountInSharesWhenNoInterest(preview, _assetsOrShares);
        }

        _assertPreviewWithdraw(preview, _assetsOrShares);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_min_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewWithdraw_min_fuzz(uint112 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        _depositForTestPreview(_assetsOrShares);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 minInput =
            _useRedeem() ? silo1.convertToShares(1) : silo1.convertToAssets(SiloMathLib._DECIMALS_OFFSET_POW);
        uint256 minPreview = _getPreview(minInput);

        if (!_interest || _collateralType() == ISilo.CollateralType.Protected) {
            _assertEqPrevAmountInSharesWhenNoInterest(minPreview, minInput);
        }

        _assertPreviewWithdraw(minPreview, minInput);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_max_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewWithdraw_max_fuzz(uint64 _assets, bool _interest) public {
        vm.assume(_assets > 0);

        _depositForTestPreview(_assets);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 maxInput = _useRedeem()
            // we can not use balance of share token, because we not sure about liquidity
            ? silo1.maxRedeem(depositor, _collateralType()) // _getShareToken().balanceOf(depositor)
            : silo1.maxWithdraw(depositor, _collateralType());

        uint256 maxPreview = _getPreview(maxInput);

        if (!_interest || _collateralType() == ISilo.CollateralType.Protected) {
            _assertEqPrevAmountInSharesWhenNoInterest(maxPreview, maxInput);
        }

        _assertPreviewWithdraw(maxPreview, maxInput);
    }

    function _depositForTestPreview(uint256 _assets) internal {
        _depositForBorrow({
            _assets: _assets,
            _depositor: depositor,
            _collateralType: _collateralType()
        });
    }

    function _createSiloUsage() internal {
        _depositForBorrow(type(uint128).max, depositor);

        _deposit(type(uint128).max, borrower, _collateralType());
        _borrow(type(uint64).max, borrower);
    }

    function _applyInterest() internal {
        uint256 ltvBefore = siloLens.getLtv(silo1, borrower);
        if (ltvBefore == 1) {
            // there is no way for this test to apply interest for 1 wei LTV
            return;
        }

        vm.warp(block.timestamp + 200 days);

        uint256 ltvAfter = siloLens.getLtv(silo1, borrower);

        emit log_named_uint("ltvBefore", ltvBefore);
        emit log_named_uint("ltvAfter", ltvAfter);

        while (ltvAfter == ltvBefore) {
            vm.warp(block.timestamp + 500 days);
            ltvAfter = siloLens.getLtv(silo1, borrower);
        }

        emit log_named_uint("ltvAfter loop", ltvAfter);

        assertGt(ltvAfter, ltvBefore, "expect any interest");
    }

    function _assertPreviewWithdraw(uint256 _preview, uint256 _assetsOrShares) internal {
        vm.assume(_preview > 0);
        vm.prank(depositor);

        uint256 results = _useRedeem()
            ? silo1.redeem(_assetsOrShares, depositor, depositor, _collateralType())
            : silo1.withdraw(_assetsOrShares, depositor, depositor, _collateralType());

        assertGt(results, 0, "expect any withdraw amount > 0");

        if (_useRedeem()) assertEq(_preview, results, "preview should give us exact result, NOT more");
        else assertEq(_preview, results, "preview should give us exact result, NOT fewer");
    }

    function _getShareToken() internal view virtual returns (IShareToken shareToken) {
        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo1));
        shareToken = _collateralType() == ISilo.CollateralType.Collateral
            ? IShareToken(collateralShareToken)
            : IShareToken(protectedShareToken);
    }

    function _getPreview(uint256 _amountToUse) internal view virtual returns (uint256 preview) {
        preview = _useRedeem()
            ? silo1.previewRedeem(_amountToUse, _collateralType())
            : silo1.previewWithdraw(_amountToUse, _collateralType());
    }

    function _useRedeem() internal pure virtual returns (bool) {
        return false;
    }

    function _collateralType() internal pure virtual returns (ISilo.CollateralType) {
        return ISilo.CollateralType.Collateral;
    }

    function _assertEqPrevAmountInSharesWhenNoInterest(uint256 _preview, uint256 _amountIn) private pure {
        if (_useRedeem()) {
            assertEq(
                _preview,
                _amountIn / SiloMathLib._DECIMALS_OFFSET_POW,
                "previewWithdraw == assets == shares, when no interest"
            );
        } else {
            assertEq(
                _preview,
                _amountIn * SiloMathLib._DECIMALS_OFFSET_POW,
                "previewWithdraw == assets == shares, when no interest"
            );
        }
    }
}
