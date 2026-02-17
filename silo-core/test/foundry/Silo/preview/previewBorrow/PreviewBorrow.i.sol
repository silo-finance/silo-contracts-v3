// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewBorrowTest
*/
contract PreviewBorrowTest is SiloLittleHelper, Test {
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
    forge test -vv --ffi --mt test_previewBorrow_freshStart_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewBorrow_freshStart_fuzz(uint112 _assetsOrShares, bool _partial) public {
        uint256 _amountIn = _partialAmount(_assetsOrShares, _partial);
        vm.assume(_amountIn > 0);

        _createScenario(false, false);

        uint256 preview = _getBorrowPreview(_amountIn);

        assertEq(preview, _amountIn, "previewWithdraw == assets == shares, when no interest");

        _assertPreviewBorrow(preview, _amountIn);
    }

    /*
    forge test -vv --ffi --mt test_previewBorrow_debt_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewBorrow_debt_fuzz(uint112 _assetsOrShares, bool _interest, bool _partial) public {
        uint256 _amountIn = _partialAmount(_assetsOrShares, _partial);
        vm.assume(_amountIn > 0);

        _createScenario(true, _interest);

        uint256 preview = _getBorrowPreview(_amountIn);
        emit log_named_uint("preview", preview);

        if (!_interest) {
            assertEq(preview, _amountIn, "preview == assets == shares, when no interest");
        }

        _assertPreviewBorrow(preview, _amountIn);
    }

    /*
    forge test -vv --ffi --mt test_previewBorrow_min_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewBorrow_min_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 1e18);

        _createScenario(_assetsOrShares, true, _interest);

        uint256 minInput = 1;
        uint256 minPreview = _getBorrowPreview(minInput);

        emit log_named_uint("_assetsOrShares", _assetsOrShares);
        emit log_named_uint("minInput", minInput);
        emit log_named_uint("minPreview", minPreview);

        _assertPreviewBorrow(minPreview, minInput);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_previewBorrow_max_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_previewBorrow_max_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 1e18);

        _createScenario(_assetsOrShares, true, _interest);

        uint256 maxInput = _borrowShares()
            ? silo1.maxBorrowShares(borrower)
            : silo1.maxBorrow(borrower);

        uint256 maxPreview = _getBorrowPreview(maxInput);

        emit log_named_uint("initial _assetsOrShares", _assetsOrShares);
        emit log_named_uint(string.concat("maxBorrow of ", _borrowShares() ? "shares" : "assets"), maxInput);
        emit log_named_uint(string.concat("maxPreview borrow ", _borrowShares() ? "shares" : "assets"), maxPreview);

        _assertPreviewBorrow(maxPreview, maxInput);
    }

    function _createScenario(bool _creteDebt, bool _interest) internal {
        _createScenario(type(uint128).max, _creteDebt, _interest);
    }

    function _createScenario(uint256 _borrowerInput, bool _creteDebt, bool _interest) internal {
        // deposit small amount at begin, because with MAX128 is hard to generate interest
        _depositForBorrow(type(uint64).max, depositor);

        if (_creteDebt) {
            address otherBorrower = makeAddr("otherBorrower");

            _deposit(type(uint64).max, otherBorrower, _collateralType());
            _borrow(uint256(type(uint64).max) * 3 / 4, otherBorrower);

            if (_interest) _applyInterest();
        }

        _deposit(_borrowerInput, borrower, _collateralType());
        _depositForBorrow(type(uint128).max - type(uint64).max, depositor);
    }

    function _applyInterest() internal {
        address otherBorrower = makeAddr("otherBorrower");

        uint256 ltvBefore = siloLens.getLtv(silo1, otherBorrower);

        if (ltvBefore == 1) {
            // there is no way for this test to apply interest for 1 wei LTV
            return;
        }

        uint256 warpTime = 10 days;
        vm.warp(block.timestamp + warpTime);

        uint256 ltvAfter = siloLens.getLtv(silo1, otherBorrower);

        emit log_named_uint("ltvBefore", ltvBefore);
        emit log_named_uint("ltvAfter", ltvAfter);

        while (ltvAfter == ltvBefore) {
            vm.warp(block.timestamp + warpTime);
            ltvAfter = siloLens.getLtv(silo1, otherBorrower);
        }

        emit log_named_uint("ltvAfter loop", ltvAfter);

        assertGt(ltvAfter, ltvBefore, "expect any interest");
    }

    function _assertPreviewBorrow(uint256 _preview, uint256 _assetsOrShares) internal {
        vm.assume(_preview > 0);

        uint256 results = _borrowShares()
            ? _borrowShares(_assetsOrShares, borrower)
            : _borrow(_assetsOrShares, borrower);

        uint256 conversionResults = _borrowShares()
            ? silo1.convertToAssets(_assetsOrShares, ISilo.AssetType.Debt)
            : silo1.convertToShares(_assetsOrShares, ISilo.AssetType.Debt);

        assertGt(results, 0, "expect any borrow amount > 0");
        assertEq(_preview, results, "preview should give us exact result");
        assertEq(_preview, conversionResults, "preview == conversion");
    }

    function _getBorrowPreview(uint256 _assetsOrShares) internal view virtual returns (uint256 preview) {
        preview =
            _borrowShares() ? silo1.previewBorrowShares(_assetsOrShares) : silo1.previewBorrow(_assetsOrShares);
    }

    function _partialAmount(uint256 _assetsOrShares, bool _partial) internal pure returns (uint256 partialAmount) {
        partialAmount = _partial ? uint256(_assetsOrShares) * 37 / 100 : _assetsOrShares;
    }

    function _borrowShares() internal pure virtual returns (bool) {
        return false;
    }

    function _collateralType() internal pure virtual returns (ISilo.CollateralType) {
        return ISilo.CollateralType.Collateral;
    }
}
