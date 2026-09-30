// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PartialLiquidationLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationLib.sol";

import {MaxRepayRawMath} from "./MaxRepayRawMath.sol";

// forge test -vv --mc MaxLiquidationTest
contract MaxLiquidationTest is Test, MaxRepayRawMath {
    uint256 internal constant _DECIMALS_POINTS = 1e18;
    uint256 internal _LT = 0.85e18;

    function setUp() public {
        _LT = 0.85e18;
    }

    /*
    forge test -vv --mt test_maxLiquidation_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 5000
    function test_maxLiquidation_fuzz(
        uint128 _sumOfCollateralAssets,
        uint128 _sumOfCollateralValue,
        uint128 _borrowerDebtAssets,
        uint64 _liquidationFee,
        uint64 _liquidationTargetLtv
    ) public {
        _test_maxLiquidation(
            _sumOfCollateralAssets,
            _sumOfCollateralValue,
            _borrowerDebtAssets,
            _liquidationFee,
            _liquidationTargetLtv
        );
    }

    /*
    forge test -vv --mt test_maxLiquidation_
    */
    function test_maxLiquidation_case1() public {
        uint128 sumOfCollateralAssets = 1000;
        uint128 sumOfCollateralValue = 1000;
        uint128 borrowerDebtAssets = 900;
        uint64 liquidationFee;
        uint64 liquidationTargetLtv = 0.5e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 798, "collateralToLiquidate");
        assertEq(debtToRepay, 800, "debtToRepay");
        assertEq(ltvAfter, 495049504950495049, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case1fee() public {
        uint128 sumOfCollateralAssets = 1000;
        uint128 sumOfCollateralValue = 1000;
        uint128 borrowerDebtAssets = 900;
        uint64 liquidationFee = 0.01e18;
        uint64 liquidationTargetLtv = 0.5e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 814, "collateralToLiquidate");
        assertEq(debtToRepay, 808, "debtToRepay");
        assertEq(ltvAfter, 494623655913978494, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case2() public {
        uint128 sumOfCollateralAssets = 1e18;
        uint128 sumOfCollateralValue = 1e18;
        uint128 borrowerDebtAssets = 0.9e18;
        uint64 liquidationFee;
        uint64 liquidationTargetLtv = 0.5e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 799999999999999998, "collateralToLiquidate");
        assertEq(debtToRepay, 0.8e18, "debtToRepay");
        assertEq(ltvAfter, 499999999999999995, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case2fee() public {
        uint128 sumOfCollateralAssets = 1e18;
        uint128 sumOfCollateralValue = 1e18;
        uint128 borrowerDebtAssets = 0.9e18;
        uint64 liquidationFee = 0.01e18;
        uint64 liquidationTargetLtv = 0.5e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 816161616161616158, "collateralToLiquidate");
        assertEq(debtToRepay, 808080808080808080, "debtToRepay");
        assertEq(ltvAfter, 499999999999999994, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case3() public {
        uint128 sumOfCollateralAssets = 1e18;
        uint128 sumOfCollateralValue = 1e18;
        uint128 borrowerDebtAssets = 0.9e18;
        uint64 liquidationFee;
        uint64 liquidationTargetLtv = 0.7e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 666666666666666664, "collateralToLiquidate");
        assertEq(debtToRepay, 666666666666666666, "debtToRepay");
        assertEq(ltvAfter, 699999999999999996, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case3fee() public {
        uint128 sumOfCollateralAssets = 1e18;
        uint128 sumOfCollateralValue = 1e18;
        uint128 borrowerDebtAssets = 0.9e18;
        uint64 liquidationFee = 0.05e18;
        uint64 liquidationTargetLtv = 0.7e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 792452830188679242, "collateralToLiquidate");
        assertEq(debtToRepay, 754716981132075471, "debtToRepay");
        assertEq(ltvAfter, 699999999999999992, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case4() public {
        uint128 sumOfCollateralAssets = 1e18;
        uint128 sumOfCollateralValue = 1e18;
        uint128 borrowerDebtAssets = 0.9e18;
        uint64 liquidationFee;
        uint64 liquidationTargetLtv = 0.1e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 899999999999999998, "collateralToLiquidate");
        assertEq(debtToRepay, 0.9e18, "debtToRepay");
        assertEq(ltvAfter, 0, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function test_maxLiquidation_case4fee() public {
        uint128 sumOfCollateralAssets = 1e18;
        uint128 sumOfCollateralValue = 1e18;
        uint128 borrowerDebtAssets = 0.9e18;
        uint64 liquidationFee = 0.3e18;
        uint64 liquidationTargetLtv = 0.1e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 999999999999999998, "collateralToLiquidate");
        assertEq(debtToRepay, 0.9e18, "debtToRepay");
        assertEq(ltvAfter, 0, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test  forge test -vv --mt test_maxLiquidation_case5
    */
    function test_maxLiquidation_case5() public {
        _LT = 0.95e18;
        uint128 sumOfCollateralAssets = 1_000_000e18;
        uint128 sumOfCollateralValue = 1_000_000e18;
        uint128 borrowerDebtAssets = 950_100e18;
        uint64 liquidationFee = 0.035e18;
        uint64 liquidationTargetLtv = 0.94e18;

        (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) = _test_maxLiquidation(
            sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, liquidationFee, liquidationTargetLtv
        );

        assertEq(collateralToLiquidate, 385738_007380073800738004, "collateralToLiquidate");
        assertEq(debtToRepay, 372693_726937269372693726, "debtToRepay");
        assertEq(collateralToLiquidate - debtToRepay, 13044_280442804428044278, "profit");
        assertEq(ltvAfter, 93_9999999999999999, "ltvAfter");
        assertEq(
            ltvAfter,
            (borrowerDebtAssets - debtToRepay) * _DECIMALS_POINTS / (sumOfCollateralValue - collateralToLiquidate),
            "ltvAfter"
        );
    }

    function _test_maxLiquidation(
        uint128 _sumOfCollateralAssets,
        uint128 _sumOfCollateralValue,
        uint128 _borrowerDebtAssets,
        uint64 _liquidationFee,
        uint64 _liquidationTargetLtv
    ) internal returns (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter) {
        emit log("vm.assume(_liquidationFee < 0.40e18)");
        vm.assume(_liquidationFee < 0.4e18); // some reasonable fee
        emit log("vm.assume(_sumOfCollateralAssets > 0)");
        vm.assume(_sumOfCollateralAssets > 0);
        // for tiny assets we doing full liquidation because it is to small to get down to expected minimal LTV
        emit log("vm.assume(_sumOfCollateralValue > 1)");
        vm.assume(_sumOfCollateralValue > 1);
        emit log("vm.assume(_borrowerDebtAssets > 1)");
        vm.assume(_borrowerDebtAssets > 1);

        // prevent overflow revert in test
        emit log("vm.assume(uint256(_borrowerDebtAssets) * _liquidationFee < type(uint128).max)");
        vm.assume(uint256(_borrowerDebtAssets) * _liquidationFee < type(uint168).max);

        emit log("vm.assume(_liquidationTargetLtv < _LT)");
        vm.assume(_liquidationTargetLtv < _LT);

        uint256 borrowerDebtValue = _borrowerDebtAssets; // assuming quote is debt token, so value is 1:1
        uint256 ltvBefore = borrowerDebtValue * 1e18 / _sumOfCollateralValue;

        // if ltv will be less, then this math should not be executed in contract
        emit log("vm.assume(ltvBefore >= _LT)");
        vm.assume(ltvBefore >= _LT);

        (collateralToLiquidate, debtToRepay) = PartialLiquidationLib.maxLiquidation(
            _sumOfCollateralAssets,
            _sumOfCollateralValue,
            _borrowerDebtAssets,
            borrowerDebtValue,
            _liquidationTargetLtv,
            _liquidationFee
        );

        emit log_named_decimal_uint("collateralToLiquidate", collateralToLiquidate, 18);
        emit log_named_decimal_uint("debtToRepay", debtToRepay, 18);

        emit log_named_decimal_uint("minExpectedLtv", _liquidationTargetLtv, 16);
        emit log_named_decimal_uint("ltvBefore", ltvBefore, 16);

        uint256 raw = _estimateMaxRepayValueRaw(
            borrowerDebtValue, _sumOfCollateralValue, _liquidationTargetLtv, _liquidationFee
        );
        emit log_named_decimal_uint("raw", raw, 18);

        uint256 deviation =
            raw > debtToRepay ? raw * _DECIMALS_POINTS / debtToRepay : debtToRepay * _DECIMALS_POINTS / raw;

        emit log_named_decimal_uint("deviation on raw calculation", deviation, 18);

        if (debtToRepay == _borrowerDebtAssets) {
            assertLe(deviation, 1.112e18, "[full] raw calculations - I'm accepting some % deviation (and dust)");
        } else {
            if (debtToRepay > 100) {
                assertLe(deviation, 1.065e18, "[partial] raw calculations - I'm accepting some % deviation");
            } else {
                assertLe(deviation, 2.0e18, "[partial] raw calculations - on tiny values we can have big deviation");
            }
        }

        ltvAfter = _ltv(
            _sumOfCollateralAssets, _sumOfCollateralValue, _borrowerDebtAssets, collateralToLiquidate, debtToRepay
        );

        emit log_named_decimal_uint("ltvAfter", ltvAfter, 16);

        if (debtToRepay == _borrowerDebtAssets) {
            emit log("full liquidation");
            // there is not really a way to verify this part other than check RAW result, what was done above
        } else {
            emit log("partial liquidation");

            assertLt(ltvAfter, _LT, "we can not expect to be wei precise. as long as we below LT, it is OK");
        }
    }

    function _ltv(
        uint256 _sumOfCollateralAssets,
        uint256 _sumOfCollateralValue,
        uint256 _borrowerDebtAssets,
        uint256 _collateralToLiquidate,
        uint256 _debtToRepay
    ) internal pure returns (uint256 ltv) {
        uint256 collateralLeft = _sumOfCollateralAssets - _collateralToLiquidate;
        uint256 collateralValueAfter = uint256(_sumOfCollateralValue) * collateralLeft / _sumOfCollateralAssets;
        if (collateralValueAfter == 0) return 0;

        uint256 debtLeft = _borrowerDebtAssets - _debtToRepay;
        ltv = debtLeft * 1e18 / collateralValueAfter;
    }
}
