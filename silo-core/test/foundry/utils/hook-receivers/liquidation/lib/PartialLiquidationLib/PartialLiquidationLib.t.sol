// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {PartialLiquidationLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationLib.sol";

import {PartialLiquidationLibChecked} from "./PartialLiquidationLibChecked.sol";
import {CalculateCollateralToLiquidateTestData} from
    "../../../../../data-readers/CalculateCollateralToLiquidateTestData.sol";
import {LiquidationPreviewTestData} from "../../../../../data-readers/LiquidationPreviewTestData.sol";
import {MaxLiquidationPreviewTestData} from "../../../../../data-readers/MaxLiquidationPreviewTestData.sol";
import {EstimateMaxRepayValueTestData} from "../../../../../data-readers/EstimateMaxRepayValueTestData.sol";
import {MaxRepayRawMath} from "./MaxRepayRawMath.sol";

// forge test -vv --mc PartialLiquidationLibTest
contract PartialLiquidationLibTest is Test, MaxRepayRawMath {
    uint256 internal constant _DECIMALS_POINTS = 1e18;

    /*
    forge test -vv --mt test_PartialLiquidationLib_collateralToLiquidate
    */
    function test_PartialLiquidationLib_collateralToLiquidate() public pure {
        // uint256 _maxDebtToCover, uint256 _totalCollateral, uint256 _liquidationFee
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(0, 0, 0), 0);
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(1, 1, 0), 1);
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(1, 1, 0.0001e18), 1);
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(10, 10, 0.0999e18), 10);
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(10, 11, 0.1e18), 11);
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(10, 9, 0.1e18), 9);
        assertEq(PartialLiquidationLib.calculateCollateralToLiquidate(100, 1000, 0.12e18), 112);
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_calculateCollateralToLiquidate_pass
    */
    function test_PartialLiquidationLib_calculateCollateralToLiquidate_pass() public {
        CalculateCollateralToLiquidateTestData json = new CalculateCollateralToLiquidateTestData();
        CalculateCollateralToLiquidateTestData.CCTLData[] memory data = json.readDataFromJson();

        assertGe(data.length, 4, "expect to have tests");

        for (uint256 i; i < data.length; i++) {
            (uint256 collateralAssets, uint256 collateralValue) = PartialLiquidationLib
                .calculateCollateralsToLiquidate(
                data[i].input.debtValueToCover,
                data[i].input.totalBorrowerCollateralValue,
                data[i].input.totalBorrowerCollateralAssets,
                data[i].input.liquidationFee
            );

            assertEq(collateralAssets, data[i].output.collateralAssets, _concatMsg(i, "expect collateralAssets"));
            assertEq(collateralValue, data[i].output.collateralValue, _concatMsg(i, "expect collateralValue"));
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_PartialLiquidationLib_liquidationPreview_pass
    */
    function test_PartialLiquidationLib_liquidationPreview_pass() public {
        LiquidationPreviewTestData json = new LiquidationPreviewTestData();
        LiquidationPreviewTestData.CELAData[] memory data = json.readDataFromJson();

        assertGe(data.length, 1, "expect to have tests");

        for (uint256 i; i < data.length; i++) {
            uint256 ltvBefore = data[i].input.totalBorrowerCollateralValue == 0
                ? 0
                : data[i].input.totalBorrowerDebtValue * 1e18 / data[i].input.totalBorrowerCollateralValue;

            PartialLiquidationLib.LiquidationPreviewParams memory params = PartialLiquidationLib
                .LiquidationPreviewParams({
                collateralLt: data[i].input.lt,
                collateralConfigAsset: address(0),
                debtConfigAsset: address(0),
                maxDebtToCover: data[i].input.maxDebtToCover,
                liquidationFee: data[i].input.liquidationFee,
                liquidationTargetLtv: data[i].input.liquidationTargetLtv
            });

            (uint256 collateralAssetsToLiquidate, uint256 debtAssetsToRepay, uint256 ltvAfterLiquidation) =
            PartialLiquidationLib.liquidationPreview(
                ltvBefore,
                data[i].input.totalBorrowerCollateralAssets,
                data[i].input.totalBorrowerCollateralValue,
                data[i].input.totalBorrowerDebtAssets,
                data[i].input.totalBorrowerDebtValue,
                params
            );

            assertEq(
                ltvAfterLiquidation,
                data[i].output.ltvAfterLiquidation,
                _concatMsg(i, "] expect ltvAfterLiquidation")
            );
            assertEq(
                collateralAssetsToLiquidate,
                data[i].output.collateralAssetsToLiquidate,
                _concatMsg(i, "] output.collateralAssetsToLiquidate")
            );
            assertEq(
                debtAssetsToRepay, data[i].output.debtAssetsToRepay, _concatMsg(i, "] expect debtAssetsToRepay")
            );
        }
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_estimateMaxRepayValue_pass
    */
    function test_PartialLiquidationLib_estimateMaxRepayValue_pass() public {
        EstimateMaxRepayValueTestData json = new EstimateMaxRepayValueTestData();
        EstimateMaxRepayValueTestData.EMRVData[] memory data = json.readDataFromJson();

        assertGe(data.length, 1, "expect to have tests");

        for (uint256 i; i < data.length; i++) {
            uint256 repayValue = PartialLiquidationLib.estimateMaxRepayValue(
                data[i].input.totalBorrowerDebtValue,
                data[i].input.totalBorrowerCollateralValue,
                data[i].input.ltvAfterLiquidation,
                data[i].input.liquidationFee
            );

            console.log("repayValue %s", repayValue);
            assertEq(repayValue, data[i].repayValue, _concatMsg(i, "expect repayValue"));
        }
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_estimateMaxRepayValue_raw
    */
    function test_PartialLiquidationLib_estimateMaxRepayValue_raw() public pure {
        // debtValue, CollateralValue, ltv, fee
        assertEq(
            PartialLiquidationLib.estimateMaxRepayValue(1e18, 1e18, 0.008e18, 0.001e18),
            _estimateMaxRepayValueRaw(1e18, 1e18, 0.008e18, 0.001e18),
            "expect raw == estimateMaxRepayValue (1)"
        );

        // simulation values
        assertEq(
            PartialLiquidationLib.estimateMaxRepayValue(85e18, 1e18, 0.79e18, 0.03e18),
            _estimateMaxRepayValueRaw(85e18, 1e18, 0.79e18, 0.03e18),
            "expect raw == estimateMaxRepayValue (2)"
        );

        // simulation values
        assertEq(
            PartialLiquidationLib.estimateMaxRepayValue(85e18, 111e18, 0.5e18, 0.1e18),
            _estimateMaxRepayValueRaw(85e18, 111e18, 0.5e18, 0.1e18),
            "expect raw == estimateMaxRepayValue (3)"
        );
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_maxLiquidationPreview_pass
    */
    function test_PartialLiquidationLib_maxLiquidationPreview_pass() public {
        MaxLiquidationPreviewTestData json = new MaxLiquidationPreviewTestData();
        MaxLiquidationPreviewTestData.MLPData[] memory data = json.readDataFromJson();

        assertGe(data.length, 1, "expect to have tests");

        for (uint256 i; i < data.length; i++) {
            (uint256 collateralValueToLiquidate, uint256 repayValue) = PartialLiquidationLib.maxLiquidationPreview(
                data[i].input.totalBorrowerCollateralValue,
                data[i].input.totalBorrowerDebtValue,
                data[i].input.ltvAfterLiquidation,
                data[i].input.liquidationFee
            );

            assertEq(
                collateralValueToLiquidate,
                data[i].output.collateralValueToLiquidate,
                _concatMsg(i, "invalid value for collateralValueToLiquidate")
            );

            assertEq(repayValue, data[i].output.repayValue, _concatMsg(i, "expect repayValue"));

            // cross check, but only when totalBorrowerDebtValue > 0
            // otherwise we will have different results for ltv because ltvAfterLiquidation will not be achievable

            // assets does not matter because it is basically related to value by price
            // so I pick here some arbitrary prices
            uint256 totalBorrowerDebtAssets = data[i].input.totalBorrowerDebtValue * 2;
            uint256 totalBorrowerCollateralAssets = data[i].input.totalBorrowerCollateralValue * 3;

            PartialLiquidationLib.LiquidationPreviewParams memory params = PartialLiquidationLib
                .LiquidationPreviewParams({
                collateralLt: data[i].input.lt,
                collateralConfigAsset: address(0),
                debtConfigAsset: address(0),
                maxDebtToCover: _assetsChunk(data[i].input.totalBorrowerDebtValue, totalBorrowerDebtAssets, repayValue),
                liquidationFee: data[i].input.liquidationFee,
                liquidationTargetLtv: data[i].input.ltvAfterLiquidation
            });

            (uint256 collateralAssetsToLiquidate, uint256 debtAssetsToRepay, uint256 ltvAfterLiquidation) =
            PartialLiquidationLib.liquidationPreview(
                // ltvBefore:
                data[i].input.totalBorrowerCollateralValue == 0
                    ? 0
                    : data[i].input.totalBorrowerDebtValue * 1e18 / data[i].input.totalBorrowerCollateralValue,
                totalBorrowerCollateralAssets,
                data[i].input.totalBorrowerCollateralValue,
                totalBorrowerDebtAssets,
                data[i].input.totalBorrowerDebtValue,
                params
            );

            emit log_named_uint("cross check #", i);

            if (data[i].output.targetLtvPossible) {
                if (ltvAfterLiquidation != data[i].input.ltvAfterLiquidation) {
                    uint256 diff = ltvAfterLiquidation > data[i].input.ltvAfterLiquidation
                        ? ltvAfterLiquidation - data[i].input.ltvAfterLiquidation
                        : data[i].input.ltvAfterLiquidation - ltvAfterLiquidation;

                    assertLe(diff, 1, _concatMsg(i, "ltvAfterLiquidation cross check"));
                }
            } else {
                assertEq(
                    ltvAfterLiquidation, 0, _concatMsg(i, "[!targetLtvPossible] ltvAfterLiquidation cross check")
                );
            }

            // liquidationPreview VS maxLiquidationPreview
            assertEq(
                collateralAssetsToLiquidate / 3, collateralValueToLiquidate, _concatMsg(i, "collateral cross check")
            );

            assertEq(debtAssetsToRepay / 2, repayValue, _concatMsg(i, "debt cross check"));
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_PartialLiquidationLib_calculateCollateralToLiquidate_math_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_PartialLiquidationLib_calculateCollateralToLiquidate_math_fuzz(
        uint256 _maxDebtToCover,
        uint128 _totalBorrowerDebtAssets,
        uint128 _totalBorrowerCollateralAssets,
        uint256 _liquidationFee,
        uint16 _quote,
        uint64 _liquidationTargetLtv
    ) public pure {
        vm.assume(_liquidationFee <= 0.1e18);
        vm.assume(_maxDebtToCover <= _totalBorrowerDebtAssets);
        vm.assume(_totalBorrowerDebtAssets > 0);
        vm.assume(_totalBorrowerCollateralAssets > 0);
        vm.assume(_quote > 0);
        vm.assume(_totalBorrowerDebtAssets < type(uint128).max / _quote);
        vm.assume(_totalBorrowerCollateralAssets < type(uint128).max / _quote);

        uint256 totalBorrowerDebtValue = _totalBorrowerDebtAssets;
        uint256 totalBorrowerCollateralValue = _totalBorrowerCollateralAssets;

        // just ro randomise
        if (_quote % 2 == 0) {
            totalBorrowerDebtValue *= _quote;
        } else {
            totalBorrowerCollateralValue *= _quote;
        }

        // we assume here, we are under 100% of ltv, otherwise it is full liquidation
        vm.assume(totalBorrowerDebtValue * _DECIMALS_POINTS / totalBorrowerCollateralValue <= _DECIMALS_POINTS);
        vm.assume(_liquidationTargetLtv < 0.8e18);

        PartialLiquidationLib.LiquidationPreviewParams memory params = PartialLiquidationLib
            .LiquidationPreviewParams({
            collateralLt: 0.8e18,
            collateralConfigAsset: address(0),
            debtConfigAsset: address(0),
            maxDebtToCover: _maxDebtToCover,
            liquidationFee: _liquidationFee,
            liquidationTargetLtv: _liquidationTargetLtv
        });

        (uint256 collateralAssetsToLiquidate, uint256 debtAssetsToRepay,) = PartialLiquidationLib.liquidationPreview(
            totalBorrowerDebtValue * _DECIMALS_POINTS / totalBorrowerCollateralValue,
            _totalBorrowerCollateralAssets,
            totalBorrowerCollateralValue,
            _totalBorrowerDebtAssets,
            totalBorrowerDebtValue,
            params
        );

        (uint256 collateralAssetsToLiquidate2, uint256 debtAssetsToRepay2,) = PartialLiquidationLibChecked
            .liquidationPreview(
            totalBorrowerDebtValue * _DECIMALS_POINTS / totalBorrowerCollateralValue,
            _totalBorrowerCollateralAssets,
            totalBorrowerCollateralValue,
            _totalBorrowerDebtAssets,
            totalBorrowerDebtValue,
            params
        );

        assertEq(collateralAssetsToLiquidate2, collateralAssetsToLiquidate, "collateralAssetsToLiquidate");
        assertEq(debtAssetsToRepay2, debtAssetsToRepay, "debtAssetsToRepay");
        // not testing ltv because stack to deep, but if others two values are good, we good on ltv
        // assertEq(ltvAfterLiquidation2, ltvAfterLiquidation, "ltvAfterLiquidation");
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_liquidationPreview_not_reverts
    */
    function test_PartialLiquidationLib_liquidationPreview_not_reverts(
        uint128 _ltvBefore,
        uint128 _sumOfCollateralAssets,
        uint128 _maxDebtToCover
    ) public pure {
        // total assets/values must be != 0, if they are not, then revert possible
        uint256 borrowerDebtAssets = 1e18;
        uint256 borrowerDebtValue = 1e18;
        uint256 sumOfCollateralValue = 1e18;

        PartialLiquidationLib.LiquidationPreviewParams memory params;
        params.maxDebtToCover = _maxDebtToCover;

        PartialLiquidationLib.liquidationPreview(
            _ltvBefore, _sumOfCollateralAssets, sumOfCollateralValue, borrowerDebtAssets, borrowerDebtValue, params
        );
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_calculateCollateralToLiquidate_not_reverts
    */
    function test_PartialLiquidationLib_calculateCollateralToLiquidate_not_reverts() public pure {
        uint256 debtValueToCover = 2e18;
        uint256 totalBorrowerCollateralValue = 20e18; // price is 2 per asset
        uint256 totalBorrowerCollateralAssets = 10e18;
        uint256 liquidationFee = 0.01e18; // 1%

        PartialLiquidationLib.calculateCollateralsToLiquidate(
            debtValueToCover, 0, totalBorrowerCollateralAssets, liquidationFee
        );

        // counter example without zero
        (uint256 collateralAssetsToLiquidate, uint256 collateralValueToLiquidate) = PartialLiquidationLib
            .calculateCollateralsToLiquidate(
            debtValueToCover, totalBorrowerCollateralValue, totalBorrowerCollateralAssets, liquidationFee
        );

        assertEq(collateralAssetsToLiquidate, 1010000000000000000);
        assertEq(collateralValueToLiquidate, 2020000000000000000);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_gas_PartialLiquidationLib_calculateCollateralToLiquidate_not_reverts
    */
    function test_gas_PartialLiquidationLib_calculateCollateralToLiquidate_not_reverts() public view {
        uint256 debtValueToCover = 2e18;
        uint256 totalBorrowerCollateralValue = 20e18; // price is 2 per asset
        uint256 totalBorrowerCollateralAssets = 10e18;
        uint256 liquidationFee = 0.01e18; // 1%

        uint256 gasStart = gasleft();
        PartialLiquidationLib.calculateCollateralsToLiquidate(
            debtValueToCover, totalBorrowerCollateralValue, totalBorrowerCollateralAssets, liquidationFee
        );
        uint256 gasEnd = gasleft();

        assertLe(gasStart - gasEnd, 1057, "optimise calculateCollateralToLiquidate()");
    }

    /*
    forge test -vv --mt test_PartialLiquidationLib_splitReceiveCollateralToLiquidate
    */
    function test_PartialLiquidationLib_splitReceiveCollateralToLiquidate() public pure {
        (uint256 fromCollateral, uint256 fromProtected) =
            PartialLiquidationLib.splitReceiveCollateralToLiquidate(0, 0);
        assertEq(fromCollateral, 0, "fromCollateral (0,0) => 0");
        assertEq(fromProtected, 0, "fromProtected (0,0) => 0");

        (fromCollateral, fromProtected) = PartialLiquidationLib.splitReceiveCollateralToLiquidate(1, 0);
        assertEq(fromCollateral, 1, "fromCollateral (1,0) => 1");
        assertEq(fromProtected, 0, "fromProtected (1,0) => 0");

        (fromCollateral, fromProtected) = PartialLiquidationLib.splitReceiveCollateralToLiquidate(0, 10);
        assertEq(fromCollateral, 0, "fromCollateral (0, 10) => 0");
        assertEq(fromProtected, 0, "fromProtected (0, 10) => 0");

        (fromCollateral, fromProtected) = PartialLiquidationLib.splitReceiveCollateralToLiquidate(10, 2);
        assertEq(fromCollateral, 8, "fromCollateral (10, 2) => 8");
        assertEq(fromProtected, 2, "fromProtected (10, 2) => 2");

        (fromCollateral, fromProtected) = PartialLiquidationLib.splitReceiveCollateralToLiquidate(5, 15);

        assertEq(fromCollateral, 0, "fromCollateral (5, 15) => 0");
        assertEq(fromProtected, 5, "fromProtected (5, 15) => 5");
    }

    /*
    forge test -vv --mt test_gas_PartialLiquidationLib_splitReceiveCollateralToLiquidate
    */
    function test_gas_PartialLiquidationLib_splitReceiveCollateralToLiquidate() public view {
        uint256 gasStart = gasleft();
        PartialLiquidationLib.splitReceiveCollateralToLiquidate(5, 15);
        uint256 gasEnd = gasleft();

        assertLe(gasStart - gasEnd, 149, "optimise splitReceiveCollateralToLiquidate");
    }

    /*
     forge test -vv --mt test_PartialLiquidationLib_maxLiquidationPreview_unchecked_fuzz
    */
    function test_PartialLiquidationLib_maxLiquidationPreview_unchecked_fuzz(
        uint128 _debtAmount,
        uint128 _collateralAmount,
        uint16 _targetLT,
        uint16 _liquidationFee
    ) public {
        vm.assume(_targetLT <= 1e18);
        vm.assume(_liquidationFee <= 1e18);

        // prices here are arbitrary
        uint256 debtValue = uint256(_debtAmount) * 50_000;
        uint256 collateralValue = uint256(_collateralAmount) * 80_000;

        (uint256 repayValue, uint256 receiveCollateral) = PartialLiquidationLib.maxLiquidationPreview(
            collateralValue, debtValue, uint256(_targetLT), uint256(_liquidationFee)
        );

        emit log_string("PartialLiquidationLib.calculateLiquidationValues PASS");

        (uint256 repayValue2, uint256 receiveCollateral2) = PartialLiquidationLibChecked.maxLiquidationPreview(
            collateralValue, debtValue, _targetLT, _liquidationFee
        );

        assertEq(repayValue, repayValue2, "repay must match value with safe math");
        assertEq(receiveCollateral, receiveCollateral2, "receiveCollateral must match value with safe math");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_valueToAssetsByRatio
    */
    function test_valueToAssetsByRatio() public pure {
        // NOTE: totalValue can not be 0

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 0, _totalAssets: 0, _totalValue: 1}), 0, "#1");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 0, _totalAssets: 1, _totalValue: 1}), 0, "#2");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 1, _totalAssets: 1, _totalValue: 1}), 1, "#3");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 1, _totalAssets: 100, _totalValue: 1}), 100, "#4");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 1, _totalAssets: 100, _totalValue: 10}), 10, "#5");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 1, _totalAssets: 100, _totalValue: 100}), 1, "#6");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 1, _totalAssets: 10, _totalValue: 100}), 0, "#7");
        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 2, _totalAssets: 10, _totalValue: 100}), 0, "#8");

        assertEq(PartialLiquidationLib.valueToAssetsByRatio({_value: 2, _totalAssets: 1000, _totalValue: 100}), 20, "#9");
    }

    function _assetsChunk(uint256 _totalValue, uint256 _totalAssets, uint256 _chunkValue)
        private
        pure
        returns (uint256 _chunkAssets)
    {
        if (_totalValue == 0) return 0;

        _chunkAssets = _chunkValue * _totalAssets;
        unchecked {
            _chunkAssets /= _totalValue;
        }
    }

    function _concatMsg(uint256 _i, string memory _msg) internal pure returns (string memory) {
        return string.concat("[", Strings.toString(_i), "] ", _msg);
    }
}
