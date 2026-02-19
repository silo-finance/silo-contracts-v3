// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract MaxLiquidationPreviewTestData {
    struct Input {
        uint256 lt;
        uint256 totalBorrowerDebtValue;
        uint256 totalBorrowerCollateralValue;
        uint256 ltvAfterLiquidation;
        uint256 liquidationFee;
    }

    struct Output {
        uint256 collateralValueToLiquidate;
        uint256 repayValue;
        bool targetLtvPossible;
    }

    struct MlpData {
        Input input;
        Output output;
    }

    function readDataFromJson() external pure returns (MlpData[] memory data) {
        data = new MlpData[](6);
        uint256 i;

        // no debt no liquidation
        data[i++] = MlpData({
            input: Input({
                lt: 0.8e18,
                totalBorrowerDebtValue: 0,
                totalBorrowerCollateralValue: 1e18,
                ltvAfterLiquidation: 0.7e18,
                liquidationFee: 0.05e18
            }),
            output: Output({collateralValueToLiquidate: 0, repayValue: 0, targetLtvPossible: false})
        });

        // when bad debt
        data[i++] = MlpData({
            input: Input({
                lt: 0.8e18,
                totalBorrowerDebtValue: 180e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0,
                liquidationFee: 0.05e18
            }),
            output: Output({collateralValueToLiquidate: 100e18, repayValue: 180e18, targetLtvPossible: true})
        });

        // if we expect ltv to be 0, we need full liquidation
        data[i++] = MlpData({
            input: Input({
                lt: 0.05e18,
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0,
                liquidationFee: 0.05e18
            }),
            output: Output({
                collateralValueToLiquidate: 80e18 + 80e18 * 500 / 1e4,
                repayValue: 80e18,
                targetLtvPossible: true
            })
        });

        // if we over 100% with fee, then we return all
        data[i++] = MlpData({
            input: Input({
                lt: 0.8e18,
                totalBorrowerDebtValue: 98e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0.97e18,
                liquidationFee: 0.031e18
            }),
            output: Output({collateralValueToLiquidate: 100e18, repayValue: 98e18, targetLtvPossible: false})
        });

        // "if we over 100% with fee, then we return all" - COUNTEREXAMPLE to above case
        // but we caught dust, so again full liquidation
        data[i++] = MlpData({
            input: Input({
                lt: 0.8e18,
                totalBorrowerDebtValue: 98e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0.97e18,
                liquidationFee: 0.0204e18 // 205-310 all produces collateral over 100%
            }),
            output: Output({ // result is 9791 LTV not 9700, but this are extreme input data
                collateralValueToLiquidate: (98e18 + 98e18 * 0.0204e18 / 1e18), // 99999200000000000000
                repayValue: 98e18,
                targetLtvPossible: false
            })
        });

        // example from excel simulation
        data[i++] = MlpData({
            input: Input({
                lt: uint256(0.7e18) * 1e18 / 0.9e18, // ~77,77%
                totalBorrowerDebtValue: 80e18,
                totalBorrowerCollateralValue: 100e18,
                ltvAfterLiquidation: 0.7e18,
                liquidationFee: 0.05e18
            }),
            output: Output({
                collateralValueToLiquidate: 39622641509433962263,
                repayValue: 37735849056603773584,
                targetLtvPossible: true
            })
        });
    }
}
