// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {SiloMathLib, ISilo, Math} from "silo-core/contracts/lib/SiloMathLib.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";

// forge test -vv --mc ConvertToSharesTest
contract ConvertToSharesTest is Test {
    struct TestCase {
        uint256 assets;
        uint256 totalAssets;
        uint256 totalShares;
        Math.Rounding rounding;
        ISilo.AssetType assetType;
        uint256 result;
    }

    uint256 public numberOfTestCases = 30;

    mapping(uint256 => TestCase) public cases;

    function setUp() public {
        cases[0] = TestCase({
            assets: 0,
            totalAssets: 0,
            totalShares: 0,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 0
        });

        cases[1] = TestCase({
            assets: 200000,
            totalAssets: 0,
            totalShares: 0,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 200000000
        });

        cases[2] = TestCase({
            assets: 100,
            totalAssets: 5000,
            totalShares: 1000,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 39
        });

        cases[3] = TestCase({
            assets: 333,
            totalAssets: 999,
            totalShares: 999,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 665
        });

        cases[4] = TestCase({
            assets: 333,
            totalAssets: 1000,
            totalShares: 999,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 665
        });

        cases[5] = TestCase({
            assets: 333,
            totalAssets: 1000,
            totalShares: 999,
            rounding: Rounding.UP,
            assetType: ISilo.AssetType.Collateral,
            result: 666
        });

        cases[6] = TestCase({
            assets: 333,
            totalAssets: 999,
            totalShares: 1000,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 666
        });

        cases[7] = TestCase({
            assets: 333,
            totalAssets: 999,
            totalShares: 1000,
            rounding: Rounding.UP,
            assetType: ISilo.AssetType.Collateral,
            result: 666
        });

        cases[8] = TestCase({
            assets: 1,
            totalAssets: 1000,
            totalShares: 1,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 1
        });

        cases[9] = TestCase({
            assets: 1,
            totalAssets: 1,
            totalShares: 1000,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 1000
        });

        cases[10] = TestCase({
            assets: 1,
            totalAssets: 1,
            totalShares: 1000,
            rounding: Rounding.UP,
            assetType: ISilo.AssetType.Collateral,
            result: 1000
        });

        cases[11] = TestCase({
            assets: 0,
            totalAssets: 0,
            totalShares: 0,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 0
        });

        cases[12] = TestCase({
            assets: 200000,
            totalAssets: 0,
            totalShares: 0,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 200000
        });

        cases[13] = TestCase({
            assets: 100,
            totalAssets: 5000,
            totalShares: 1000,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 20
        });

        cases[14] = TestCase({
            assets: 333,
            totalAssets: 999,
            totalShares: 999,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 333
        });

        cases[15] = TestCase({
            assets: 333,
            totalAssets: 1000,
            totalShares: 999,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 332
        });

        cases[16] = TestCase({
            assets: 333,
            totalAssets: 1000,
            totalShares: 999,
            rounding: Rounding.UP,
            assetType: ISilo.AssetType.Debt,
            result: 333
        });

        cases[17] = TestCase({
            assets: 333,
            totalAssets: 999,
            totalShares: 1000,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 333
        });

        cases[18] = TestCase({
            assets: 333,
            totalAssets: 999,
            totalShares: 1000,
            rounding: Rounding.UP,
            assetType: ISilo.AssetType.Debt,
            result: 334
        });

        cases[19] = TestCase({
            assets: 1,
            totalAssets: 1000,
            totalShares: 1,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 0
        });

        cases[20] = TestCase({
            assets: 1,
            totalAssets: 1,
            totalShares: 1000,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Debt,
            result: 1000
        });

        cases[21] = TestCase({
            assets: 1,
            totalAssets: 1,
            totalShares: 1000,
            rounding: Rounding.UP,
            assetType: ISilo.AssetType.Debt,
            result: 1000
        });

        cases[22] = TestCase({
            assets: 1,
            totalAssets: 4, // dust
            totalShares: 0,
            rounding: Rounding.DOWN,
            assetType: ISilo.AssetType.Collateral,
            result: 1000
        });
    }

    /*
    forge test -vv --mt test_convertToShares
    */
    function test_convertToShares_singleCase() public view {
        for (uint256 index = 0; index < numberOfTestCases; index++) {
            assertEq(
                SiloMathLib.convertToShares(
                    cases[index].assets,
                    cases[index].totalAssets,
                    cases[index].totalShares,
                    cases[index].rounding,
                    cases[index].assetType
                ),
                cases[index].result,
                string.concat("TestCase: ", Strings.toString(index))
            );
        }
    }

    /*
    forge test -vv --mt test_convertToShares_withDust_from1
    */
    function test_convertToShares_withDust_from1() public pure {
        ISilo.AssetType assetType = ISilo.AssetType.Collateral;

        uint256 totalAssets = 4; // dust
        uint256 totalShares;
        uint256 toDeposit = 1;

        uint256 shares1 = SiloMathLib.convertToShares({
            _assets: toDeposit,
            _totalAssets: totalAssets,
            _totalShares: totalShares,
            _assetType: assetType,
            _rounding: Rounding.DEPOSIT_TO_SHARES
        });

        totalAssets += toDeposit;
        totalShares += shares1;

        assertEq(shares1, 1000, "#1 got shares");
        assertEq(totalAssets, 4 + 1, "#2 totalAssets = dust + deposit");

        toDeposit = 100;

        uint256 shares2 = SiloMathLib.convertToShares({
            _assets: toDeposit,
            _totalAssets: totalAssets,
            _totalShares: totalShares,
            _assetType: assetType,
            _rounding: Rounding.DEPOSIT_TO_SHARES
        });

        totalAssets += toDeposit;
        totalShares += shares2;

        assertEq(shares2, 33333, "#2 got shares"); // 100 * (1 + 1) / (5 + 1) = 33.33 => down => 33
        assertEq(totalAssets, 4 + 1 + 100, "#2 totalAssets");
        assertEq(totalShares, 34333, "#2 totalShares");

        assertEq(
            SiloMathLib.convertToAssets({
                _shares: shares1,
                _totalAssets: totalAssets,
                _totalShares: totalShares,
                _assetType: assetType,
                _rounding: Rounding.DEPOSIT_TO_ASSETS
            }),
            4,
            "user deposit 1 but with dust got 4"
        );

        assertEq(
            SiloMathLib.convertToAssets({
                _shares: shares2,
                _totalAssets: totalAssets,
                _totalShares: totalShares,
                _assetType: assetType,
                _rounding: Rounding.DEPOSIT_TO_ASSETS
            }),
            100,
            "user deposit 100 and got 100 back"
        );

        // there will be 1 dust left after withdrawals
    }
}
