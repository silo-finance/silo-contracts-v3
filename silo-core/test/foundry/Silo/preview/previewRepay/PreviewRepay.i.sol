// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewRepayTest
*/
contract PreviewRepayTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;
    address immutable depositor;
    address immutable borrower;

    constructor() {
        depositor = makeAddr("Depositor");
        borrower = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_previewRepay_freshStart_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewRepay_freshStart_fuzz(uint112 _assetsOrShares, bool _partial) public {
        uint256 _amountIn = _partialAmount(_assetsOrShares, _partial);
        vm.assume(_amountIn > 0);

        uint256 maxRepay = _createScenario(false, false);
        vm.assume(_amountIn <= maxRepay);

        uint256 preview = _getRepayPreview(_amountIn);

        assertEq(preview, _amountIn, "previewRepay == assets == shares, when no interest");

        _assertPreviewRepay(preview, _amountIn);
    }

    /*
    forge test -vv --ffi --mt test_previewRepay_debt_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewRepay_debt_fuzz(uint112 _assetsOrShares, bool _interest, bool _partial) public {
        uint256 _amountIn = _partialAmount(_assetsOrShares, _partial);
        vm.assume(_amountIn > 0);

        uint256 maxRepay = _createScenario(true, _interest);
        vm.assume(_amountIn <= maxRepay);

        uint256 preview = _getRepayPreview(_amountIn);

        if (!_interest) {
            assertEq(preview, _amountIn, "preview == assets == shares, when no interest");
        }

        _assertPreviewRepay(preview, _amountIn);
    }

    /*
    forge test -vv --ffi --mt test_previewRepay_min_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewRepay_min_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 1e18);

        _createScenario(_assetsOrShares, true, _interest);

        uint256 minInput = 1;
        uint256 minPreview = _getRepayPreview(minInput);

        _assertPreviewRepay(minPreview, minInput);
    }

    /*
    forge test -vv --ffi --mt test_previewRepay_max_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewRepay_max_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 1e18);

        uint256 maxInput = _createScenario(_assetsOrShares, true, _interest);
        uint256 maxPreview = _getRepayPreview(maxInput);

        _assertPreviewRepay(maxPreview, maxInput);
    }

    function _createScenario(bool _otherBorrower, bool _interest) internal returns (uint256 maxRepay) {
        return _createScenario(type(uint112).max, _otherBorrower, _interest);
    }

    function _createScenario(uint112 _borrowerInput, bool _otherBorrower, bool _interest)
        internal
        returns (uint256 maxRepay)
    {
        _depositForBorrow(uint256(type(uint112).max) * 2, depositor);

        _deposit(_borrowerInput, borrower);
        _borrow(uint256(_borrowerInput) * 3 / 4, borrower);

        if (_otherBorrower) {
            address otherBorrower = makeAddr("otherBorrower");

            _deposit(type(uint96).max, otherBorrower);
            _borrow(uint256(type(uint96).max) * 3 / 4, otherBorrower);
        }

        if (_interest) _applyInterest();

        return _getMaxRepay();
    }

    function _applyInterest() internal {
        uint256 ltvBefore = siloLens.getLtv(silo1, borrower);

        if (ltvBefore == 1) {
            // there is no way for this test to apply interest for 1 wei LTV
            return;
        }

        uint256 warpTime = 20 days;
        vm.warp(block.timestamp + warpTime);

        uint256 ltvAfter = siloLens.getLtv(silo1, borrower);

        while (ltvAfter == ltvBefore) {
            vm.warp(block.timestamp + warpTime);
            ltvAfter = siloLens.getLtv(silo1, borrower);
        }

        emit log_named_uint("ltvAfter loop", ltvAfter);

        assertGt(ltvAfter, ltvBefore, "expect any interest");
    }

    function _assertPreviewRepay(uint256 _preview, uint256 _assetsOrShares) internal {
        vm.assume(_preview > 0);

        uint256 results =
            _useShares() ? _repayShares(_preview, _assetsOrShares, borrower) : _repay(_assetsOrShares, borrower);

        assertGt(results, 0, "expect any borrow amount > 0");
        assertEq(_preview, results, "preview should give us exact result");
    }

    function _getMaxRepay() internal view virtual returns (uint256 max) {
        max = _useShares() ? silo1.maxRepayShares(borrower) : silo1.maxRepay(borrower);
    }

    function _getRepayPreview(uint256 _assetsOrShares) internal view virtual returns (uint256 preview) {
        preview = _useShares() ? silo1.previewRepayShares(_assetsOrShares) : silo1.previewRepay(_assetsOrShares);
    }

    function _partialAmount(uint256 _assetsOrShares, bool _partial) internal pure returns (uint256 partialAmount) {
        partialAmount = _partial ? uint256(_assetsOrShares) * 37 / 100 : _assetsOrShares;
    }

    function _useShares() internal pure virtual returns (bool) {
        return false;
    }
}
