// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract EstimateMaxRepayValueTestData {
    struct Input {
        uint256 totalBorrowerDebtValue;
        uint256 totalBorrowerCollateralValue;
        uint256 ltvAfterLiquidation;
        uint256 liquidationFee;
    }

    struct EMRVData {
        Input input;
        uint256 repayValue;
    }

    function readDataFromJson() external pure returns (EMRVData[] memory data) {
        data = new EMRVData[](8);
        uint256 i;

        // no debt no liquidation
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 0,
                totalBorrowerCollateralValue: 1e18,
                ltvAfterLiquidation: 0.7e18,
                liquidationFee: 0.05e18
            }),
            repayValue: 0
        });

        // when target LTV higher than current
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 1e18,
                totalBorrowerCollateralValue: 2e18,
                ltvAfterLiquidation: 0.5001e18,
                liquidationFee: 0.05e18
            }),
            repayValue: 0
        });

        // if BP - LT - LT * f -> negative
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0.79e18,
                liquidationFee: 0.2659e18
            }),
            repayValue: 80e18 // we repay all because we never get as low as 79%
        });

        // if BP - LT - LT * f -> negative - COUNTER EXAMPLE
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0.79e18, // impossible to get here with such high fee
                liquidationFee: 0.2658e18
            }),
            repayValue: 80e18
        });

        // when bad debt
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 180e18,
                totalBorrowerCollateralValue: 180e18,
                ltvAfterLiquidation: 0.7e18,
                liquidationFee: 0.0001e18
            }),
            repayValue: 180e18
        });

        // if we expect ltv to be 0, we need full liquidation
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0,
                liquidationFee: 0.05e18
            }),
            repayValue: 80e18
        });

        // example from exec simulation
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0.7e18,
                liquidationFee: 0.05e18
            }),
            repayValue: 37735849056603773584
        });

        // example from exec simulation
        data[i++] = EMRVData({
            input: Input({
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 112e18,
                ltvAfterLiquidation: 0.7e18,
                liquidationFee: 0.05e18
            }),
            repayValue: 6037735849056603773
        });
    }
}
