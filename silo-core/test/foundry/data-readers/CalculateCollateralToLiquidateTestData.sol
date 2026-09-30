// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract CalculateCollateralToLiquidateTestData {
    // must be in alphabetic order
    struct Input {
        uint256 debtValueToCover;
        uint256 liquidationFee;
        uint256 totalBorrowerCollateralAssets;
        uint256 totalBorrowerCollateralValue;
    }

    struct Output {
        uint256 collateralAssets;
        uint256 collateralValue;
    }

    struct CCTLData {
        Input input;
        Output output;
    }

    function readDataFromJson() external pure returns (CCTLData[] memory data) {
        data = new CCTLData[](6);
        uint256 i;

        data[i++] = CCTLData({
            input: Input({
                debtValueToCover: 0,
                totalBorrowerCollateralValue: 1,
                totalBorrowerCollateralAssets: 1,
                liquidationFee: 0
            }),
            output: Output({collateralAssets: 0, collateralValue: 0})
        });

        data[i++] = CCTLData({
            input: Input({
                debtValueToCover: 1,
                totalBorrowerCollateralValue: 1,
                totalBorrowerCollateralAssets: 1,
                liquidationFee: 1
            }),
            output: Output({collateralAssets: 1, collateralValue: 1})
        });

        data[i++] = CCTLData({
            input: Input({
                debtValueToCover: 2e18,
                totalBorrowerCollateralAssets: 10e18,
                totalBorrowerCollateralValue: 2e18,
                liquidationFee: 0.01e18
            }),
            output: Output({collateralValue: 2e18, collateralAssets: 10e18})
        });

        data[i++] = CCTLData({
            input: Input({
                debtValueToCover: 2e18,
                totalBorrowerCollateralAssets: 10e18,
                totalBorrowerCollateralValue: 40e18, // 1token has value of 4e18
                liquidationFee: 0.01e18
            }),
            output: Output({
                collateralValue: 2e18 + 2e18 * 0.01e18 / 1e18, // debt + fee
                collateralAssets: (2e18 + 2e18 * 0.01e18 / 1e18) * 1e18 / 4e18 // value / token value => token assets
            })
        });

        data[i++] = CCTLData({
            input: Input({
                debtValueToCover: 1e18,
                totalBorrowerCollateralAssets: 100e18,
                totalBorrowerCollateralValue: 20e18, // 1token has value of 20 / 100 => 0.2e18
                liquidationFee: 0.5e18
            }),
            output: Output({
                collateralValue: 1e18 + 1e18 * 0.5e18 / 1e18, // debt + fee
                collateralAssets: (1e18 + 1e18 * 0.5e18 / 1e18) * 1e18 / 0.2e18 // value / token value => token assets
            })
        });

        data[i++] = CCTLData({
            input: Input({
                debtValueToCover: 2e18,
                totalBorrowerCollateralAssets: 10e18,
                totalBorrowerCollateralValue: 1e18, // 1token has value of 0.1e18
                liquidationFee: 0.01e18
            }),
            output: Output({
                collateralValue: 1e18, // all
                collateralAssets: 10e18 // all
            })
        });
    }
}
