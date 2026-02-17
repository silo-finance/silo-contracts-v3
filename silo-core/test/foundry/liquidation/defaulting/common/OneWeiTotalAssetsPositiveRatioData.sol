// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";

struct SplitInputData {
    uint8 id;
    uint256 assetsToLiquidate;
    uint256 expectedKeeperShares;
    uint256 expectedLendersShares;
    uint256 totalAssets;
    uint256 totalShares;
}

contract OneWeiTotalAssetsPositiveRatioData {
    using Strings for uint8;
    using Strings for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;
    uint256 internal constant _KEEPER_FEE = 0.2e18;
    uint256 internal constant _LIQUIDATION_FEE = 0.1e18;

    SplitInputData[] public data;

    constructor() {
        uint256 oneWeiAsset = 1;

        add(
            SplitInputData({
                id: 1,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 109,
                expectedLendersShares: 5891, // because of offset
                totalAssets: oneWeiAsset,
                totalShares: 11000
            })
        );

        add(
            SplitInputData({
                id: 2,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 19,
                expectedLendersShares: 1031,
                totalAssets: oneWeiAsset,
                totalShares: 1100
            })
        );

        add(
            SplitInputData({
                id: 3,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 10,
                expectedLendersShares: 545, // because of offset
                totalAssets: oneWeiAsset,
                totalShares: 110
            })
        );

        add(
            SplitInputData({
                id: 4,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 18,
                expectedLendersShares: 982,
                totalAssets: oneWeiAsset,
                totalShares: 1000
            })
        );

        add(
            SplitInputData({
                id: 5,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 9,
                expectedLendersShares: 491,
                totalAssets: oneWeiAsset,
                totalShares: 1
            })
        );

        add(
            SplitInputData({
                id: 6,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 9,
                expectedLendersShares: 492,
                totalAssets: oneWeiAsset,
                totalShares: 2
            })
        );

        add(
            SplitInputData({
                id: 7,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 9,
                expectedLendersShares: 518,
                totalAssets: oneWeiAsset,
                totalShares: 55
            })
        );

        add(
            SplitInputData({
                id: 8,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 9,
                expectedLendersShares: 534,
                totalAssets: oneWeiAsset,
                totalShares: 87
            })
        );

        add(
            SplitInputData({
                id: 9,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 10,
                expectedLendersShares: 544,
                totalAssets: oneWeiAsset,
                totalShares: 109
            })
        );
    }

    function add(SplitInputData memory _data) public {
        require(
            _data.id == data.length + 1,
            string.concat("id got ", _data.id.toString(), " expected ", (data.length + 1).toString())
        );

        require(_data.totalAssets <= _data.totalShares, "totalAssets must be less than totalShares (positive ratio)");
        require(_data.assetsToLiquidate == 1, "assetsToLiquidate must be 1 for this cases");
        require(_data.totalAssets == 1, "totalAssets must be 1 for this cases");

        data.push(_data);
    }

    function getData() external view returns (SplitInputData[] memory) {
        return data;
    }
}
