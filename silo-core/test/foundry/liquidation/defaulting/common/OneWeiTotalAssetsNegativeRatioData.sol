// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {SplitInputData} from "./OneWeiTotalAssetsPositiveRatioData.sol";

contract OneWeiTotalAssetsNegativeRatioData {
    using Strings for uint8;
    using Strings for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;
    uint256 internal constant _KEEPER_FEE = 0.2e18;
    uint256 internal constant _LIQUIDATION_FEE = 0.1e18;

    SplitInputData[] public data;

    constructor() {
        uint256 oneWeiAsset = 1;

        // this looks weird, that we getting 100% shares for 0.01 assets, but it is because of offset math
        add(
            SplitInputData({
                id: 1,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 0,
                expectedLendersShares: 10,
                totalAssets: 100,
                totalShares: 10
            })
        );

        add(
            SplitInputData({
                id: 2,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 0,
                expectedLendersShares: 10,
                totalAssets: 100,
                totalShares: 33
            })
        );

        add(
            SplitInputData({
                id: 3,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 0,
                expectedLendersShares: 0,
                totalAssets: 3333,
                totalShares: 1000
            })
        );

        add(
            SplitInputData({
                id: 4,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 0,
                expectedLendersShares: 0,
                totalAssets: 1e18,
                totalShares: 1000
            })
        );

        add(
            SplitInputData({
                id: 5,
                assetsToLiquidate: oneWeiAsset,
                expectedKeeperShares: 0,
                expectedLendersShares: 1,
                totalAssets: 1e18,
                totalShares: 1e18
            })
        );
    }

    function add(SplitInputData memory _data) public {
        require(
            _data.totalAssets >= _data.totalShares,
            "totalAssets must be greater than or equal to totalShares (negative ratio)"
        );

        require(
            _data.id == data.length + 1,
            string.concat("id got ", _data.id.toString(), " expected ", (data.length + 1).toString())
        );
        require(_data.assetsToLiquidate == 1, "assetsToLiquidate must be 1 for this cases");

        data.push(_data);
    }

    function getData() external view returns (SplitInputData[] memory) {
        return data;
    }
}
