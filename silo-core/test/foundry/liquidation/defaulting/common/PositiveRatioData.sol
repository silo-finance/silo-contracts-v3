// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {SplitInputData} from "./OneWeiTotalAssetsPositiveRatioData.sol";

contract PositiveRatioData {
    using Strings for uint8;
    using Strings for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;
    uint256 internal constant _KEEPER_FEE = 0.2e18;
    uint256 internal constant _LIQUIDATION_FEE = 0.1e18;

    SplitInputData[] public data;

    constructor() {
        // this case will probably revert tx because 99 shares most likely is not in posession of borrower
        // we getting this weird result because we using offset 1e3
        add(
            SplitInputData({
                id: 1,
                assetsToLiquidate: 1,
                expectedKeeperShares: 1,
                expectedLendersShares: 99,
                totalAssets: 10,
                totalShares: 100
            })
        );

        add(
            SplitInputData({
                id: 2,
                assetsToLiquidate: 1,
                expectedKeeperShares: 2,
                expectedLendersShares: 134, // because of offset
                totalAssets: 10,
                totalShares: 500
            })
        );

        add(
            SplitInputData({
                id: 3,
                assetsToLiquidate: 1,
                expectedKeeperShares: 18,
                expectedLendersShares: 982,
                totalAssets: 1,
                totalShares: 1000
            })
        );

        add(
            SplitInputData({
                id: 4,
                assetsToLiquidate: 2,
                expectedKeeperShares: 24,
                expectedLendersShares: 1309, // because of offset
                totalAssets: 2,
                totalShares: 1000
            })
        );

        add(
            SplitInputData({
                id: 5,
                assetsToLiquidate: 1,
                expectedKeeperShares: 27,
                expectedLendersShares: 1473, // huge ronding error
                totalAssets: 1,
                totalShares: 2000
            })
        );

        add(
            SplitInputData({
                id: 6,
                assetsToLiquidate: 1,
                expectedKeeperShares: 18,
                expectedLendersShares: 982,
                totalAssets: 2,
                totalShares: 2000
            })
        );

        add(
            SplitInputData({
                id: 7,
                assetsToLiquidate: 2,
                expectedKeeperShares: 18 * 2,
                expectedLendersShares: 982 * 2,
                totalAssets: 2,
                totalShares: 2000
            })
        );

        add(
            SplitInputData({
                id: 8,
                assetsToLiquidate: 1e18,
                expectedKeeperShares: 18181818181818181818,
                expectedLendersShares: 981.818181818181818182e18, // ~2% for keeper
                totalAssets: 1e18,
                totalShares: 1e21
            })
        );

        add(
            SplitInputData({
                id: 9,
                assetsToLiquidate: 1,
                expectedKeeperShares: 18,
                expectedLendersShares: 982,
                totalAssets: 1e18,
                totalShares: 1e21
            })
        );

        add(
            SplitInputData({
                id: 10,
                assetsToLiquidate: 3,
                expectedKeeperShares: 18 * 3,
                expectedLendersShares: 982 * 3,
                totalAssets: 1e18,
                totalShares: 1e21
            })
        );

        add(
            SplitInputData({
                id: 11,
                assetsToLiquidate: 5,
                expectedKeeperShares: 18 * 5,
                expectedLendersShares: 982 * 5,
                totalAssets: 1e18,
                totalShares: 1e21
            })
        );

        add(
            SplitInputData({
                id: 12,
                assetsToLiquidate: 3333332,
                expectedKeeperShares: 60606036,
                expectedLendersShares: 3272725964,
                totalAssets: 3333333,
                totalShares: 3272725964 + 60606036 + 1000 // 3333333000
            })
        );

        add(
            SplitInputData({
                id: 13,
                assetsToLiquidate: 3333333,
                expectedKeeperShares: 60606036 + 18,
                expectedLendersShares: 3272725964 + 982,
                totalAssets: 3333333,
                totalShares: 3333333000
            })
        );
    }

    function add(SplitInputData memory _data) public {
        require(_data.totalAssets <= _data.totalShares, "totalAssets must be less than totalShares (positive ratio)");
        require(
            _data.id == data.length + 1,
            string.concat("id got ", _data.id.toString(), " expected ", (data.length + 1).toString())
        );

        data.push(_data);
    }

    function getData() external view returns (SplitInputData[] memory) {
        return data;
    }
}
