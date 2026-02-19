// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxBorrowSharesTest
*/
contract MaxBorrowSharesTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;
    address immutable DEPOSITOR;
    address immutable BORROWER;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        BORROWER = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_maxBorrowShares_noCollateral
    */
    function test_maxBorrowShares_noCollateral() public {
        _assertMaxBorrowSharesIsZeroAtTheEnd();
    }

    function _maxBorrowShares_noCollateral() internal {
        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);
        assertEq(maxBorrowShares, 0, "no collateral - no borrowShares");

        _assertMaxBorrowSharesIsZeroAtTheEnd();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowShares_withCollateral_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxBorrowShares_withCollateral_fuzz(uint128 _collateral, uint128 _liquidity) public {
        // (uint128 _collateral, uint128 _liquidity) = (3, 2);
        vm.assume(_liquidity > 0);
        vm.assume(_collateral > 0);

        _depositForBorrow(_liquidity, DEPOSITOR);
        _deposit(_collateral, BORROWER);

        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);
        vm.assume(maxBorrowShares > 0);

        _assertWeCanNotBorrowAboveMax(maxBorrowShares, 4);

        _assertMaxBorrowSharesIsZeroAtTheEnd(1);
    }

    /*
    forge test -vv --ffi --mt test_maxBorrowShares_collateralButNoLiquidity
    */
    /// forge-config: core_test.fuzz.runs = 100
    function test_maxBorrowShares_collateralButNoLiquidity_fuzz(uint128 _collateral) public {
        // uint128 _collateral = 2;
        vm.assume(_collateral > uint128(3)); // to allow any borrowShares twice

        _deposit(_collateral, BORROWER);

        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);

        assertEq(maxBorrowShares, 0, "if 2 tokens and no liquidity, max should be 0");

        _assertWeCanNotBorrowAboveMax(maxBorrowShares);
        _assertMaxBorrowSharesIsZeroAtTheEnd();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowShares_withDebt
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxBorrowShares_withDebt_fuzz(uint128 _collateral, uint128 _liquidity) public {
        vm.assume(_collateral > 0);
        vm.assume(_liquidity > 0);

        _deposit(_collateral, BORROWER);
        _depositForBorrow(_liquidity, DEPOSITOR);

        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);

        uint256 firstBorrow = maxBorrowShares / 3;
        vm.assume(firstBorrow > 0);
        _borrowShares(firstBorrow, BORROWER);

        // now we have debt

        maxBorrowShares = silo1.maxBorrowShares(BORROWER);

        _assertWeCanNotBorrowAboveMax(maxBorrowShares, 5);
        _assertMaxBorrowSharesIsZeroAtTheEnd(2);
    }

    /*
    forge test -vv --ffi --mt test_maxBorrowShares_withInterest_
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxBorrowShares_withInterest_fuzz(uint128 _collateral, uint128 _liquidity) public {
        _maxBorrowShares_withInterest_fuzz(_collateral, _liquidity, ISilo.CollateralType.Collateral);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowShares_withInterest_protected_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxBorrowShares_withInterest_protected_fuzz(uint128 _collateral, uint128 _liquidity)
        public
    {
        _maxBorrowShares_withInterest_fuzz(_collateral, _liquidity, ISilo.CollateralType.Protected);
    }

    function _maxBorrowShares_withInterest_fuzz(
        uint128 _collateral,
        uint128 _liquidity,
        ISilo.CollateralType _collateralType
    ) private {
        vm.assume(_collateral > 0);
        vm.assume(_liquidity > 0);

        _deposit(_collateral, BORROWER, _collateralType);
        _depositForBorrow(_liquidity, DEPOSITOR);

        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);
        uint256 firstBorrow = maxBorrowShares / 3;
        emit log_named_uint("____ firstBorrow", firstBorrow);

        vm.assume(firstBorrow > 0);
        _borrowShares(firstBorrow, BORROWER);

        // now we have debt
        vm.warp(block.timestamp + 100 days);

        maxBorrowShares = silo1.maxBorrowShares(BORROWER);
        emit log_named_uint("____ maxBorrowShares", maxBorrowShares);

        _assertWeCanNotBorrowAboveMax(maxBorrowShares, 7);
        _assertMaxBorrowSharesIsZeroAtTheEnd(2);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowShares_repayWithInterest_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 5000
    function test_maxBorrowShares_repayWithInterest_fuzz(uint64 _collateral, uint128 _liquidity) public {
        // (uint64 _collateral, uint128 _liquidity) = (59, 10247839164);
        _maxBorrowShares_repayWithInterest_fuzz(_collateral, _liquidity, ISilo.CollateralType.Collateral);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowShares_repayWithInterest_protected_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 5000
    function test_maxBorrowShares_repayWithInterest_protected_fuzz(uint64 _collateral, uint128 _liquidity)
        public
    {
        _maxBorrowShares_repayWithInterest_fuzz(_collateral, _liquidity, ISilo.CollateralType.Protected);
    }

    function _maxBorrowShares_repayWithInterest_fuzz(
        uint64 _collateral,
        uint128 _liquidity,
        ISilo.CollateralType _collateralType
    ) private {
        vm.assume(_collateral > 0);
        vm.assume(_liquidity > 0);

        _deposit(_collateral, BORROWER, _collateralType);
        _depositForBorrow(_liquidity, DEPOSITOR);

        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);
        uint256 firstBorrow = maxBorrowShares / 3;
        emit log_named_uint("____ firstBorrow", firstBorrow);

        vm.assume(firstBorrow > 0);
        _borrowShares(firstBorrow, BORROWER);

        // now we have debt
        vm.warp(block.timestamp + 100 days);
        emit log("----- time travel -----");

        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        token1.setOnDemand(true);
        uint256 debt = IShareToken(debtShareToken).balanceOf(BORROWER);
        emit log_named_decimal_uint("user shares", debt, 18);
        uint256 debtToRepay = debt * 9 / 10 == 0 ? 1 : debt * 9 / 10;
        emit log_named_decimal_uint("debtToRepay", debtToRepay, 18);

        _repayShares(1, debtToRepay, BORROWER);
        token1.setOnDemand(false);

        // maybe we have some debt left, maybe not

        maxBorrowShares = silo1.maxBorrowShares(BORROWER);
        emit log_named_uint("____ maxBorrowShares", maxBorrowShares);

        _assertWeCanNotBorrowAboveMax(maxBorrowShares, 36);
        _assertMaxBorrowSharesIsZeroAtTheEnd(36);
    }

    function _assertWeCanNotBorrowAboveMax(uint256 _maxBorrow) internal {
        _assertWeCanNotBorrowAboveMax(_maxBorrow, 1);
    }

    /// @param _precision is needed because we count for precision error and we allow for 1 wei diff
    function _assertWeCanNotBorrowAboveMax(uint256 _maxBorrowShares, uint256 _precision) internal {
        emit log_named_uint("------- QA: _assertWeCanNotBorrowAboveMax shares", _maxBorrowShares);
        emit log_named_uint("------- QA: _assertWeCanNotBorrowAboveMax _precision", _precision);

        uint256 toBorrow = _maxBorrowShares + _precision;

        uint256 liquidity = silo1.getLiquidity();
        uint256 maxBorrowAssets = silo1.convertToAssets(_maxBorrowShares, ISilo.AssetType.Debt);

        emit log_named_decimal_uint("[_assertWeCanNotBorrowAboveMax] maxBorrowAssets", maxBorrowAssets, 18);
        emit log_named_decimal_uint("[_assertWeCanNotBorrowAboveMax] liquidity", liquidity, 18);
        emit log_named_decimal_uint(
            "[_assertWeCanNotBorrowAboveMax] balanceOf", token1.balanceOf(address(silo1)), 18
        );
        emit log_named_decimal_uint("[_assertWeCanNotBorrowAboveMax]  toBorrow", toBorrow, 18);

        if (maxBorrowAssets > liquidity) {
            emit log("MAX returned shares, that translate for TOO MUCH assets");
            // assertLe(maxBorrowAssets, liquidity, "MAX returned shares, that translate for TOO MUCH assets");
        }

        vm.prank(BORROWER);
        try silo1.borrowShares(toBorrow, BORROWER, BORROWER) returns (uint256) {
            revert("[borrowShares] we expect tx to be reverted!");
        } catch (bytes memory data) {
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 errorType = bytes4(data);

            bytes4 error1 = bytes4(keccak256(abi.encodePacked("NotEnoughLiquidity()")));
            bytes4 error2 = bytes4(keccak256(abi.encodePacked("AboveMaxLtv()")));

            if (errorType != error1 && errorType != error2) {
                revert("we need to revert with NotEnoughLiquidity or AboveMaxLtv");
            }
        }

        if (_maxBorrowShares > 0) {
            emit log_named_decimal_uint(
                "[_assertWeCanNotBorrowAboveMax] _maxBorrow > 0 YES, borrowing max", _maxBorrowShares, 18
            );
            vm.prank(BORROWER);
            silo1.borrowShares(_maxBorrowShares, BORROWER, BORROWER);
        }
    }

    function _assertMaxBorrowSharesIsZeroAtTheEnd() internal {
        _assertMaxBorrowSharesIsZeroAtTheEnd(0);
    }

    function _assertMaxBorrowSharesIsZeroAtTheEnd(uint256 _precision) internal {
        emit log_named_uint(
            "=================== _assertMaxBorrowIsZeroAtTheEnd =================== +/-", _precision
        );

        uint256 maxBorrowShares = silo1.maxBorrowShares(BORROWER);

        assertLe(
            maxBorrowShares,
            _precision,
            string.concat("at this point max should return 0 +/-", string(abi.encodePacked(_precision)))
        );
    }
}
