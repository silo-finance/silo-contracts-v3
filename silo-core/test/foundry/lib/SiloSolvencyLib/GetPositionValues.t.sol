// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SiloSolvencyLib} from "silo-core/contracts/lib/SiloSolvencyLib.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {OraclesHelper} from "../../_common/OraclesHelper.sol";

/*
forge test -vv --mc GetPositionValuesTest
*/
contract GetPositionValuesTest is Test, OraclesHelper {
    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    /*
    forge test -vv --mt test_SiloSolvencyLib_PRECISION_DECIMALS
    */
    function test_SiloSolvencyLib_PRECISION_DECIMALS() public pure {
        assertEq(_PRECISION_DECIMALS, SiloSolvencyLib._PRECISION_DECIMALS, "_PRECISION_DECIMALS");
    }

    /*
    forge test -vv --mt test_SiloSolvencyLib_getPositionValues_noOracle
    */
    function test_SiloSolvencyLib_getPositionValues_noOracle() public view {
        ISiloOracle noOracle;
        uint256 collateralAssets = 20;
        uint256 protectedAssets = 10;
        uint256 debtAssets = 3;

        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.LtvData({
            collateralOracle: noOracle,
            debtOracle: noOracle,
            borrowerProtectedAssets: protectedAssets,
            borrowerCollateralAssets: collateralAssets,
            borrowerDebtAssets: debtAssets
        });

        address any = address(1);

        (uint256 collateralValue, uint256 debtValue) = SiloSolvencyLib.getPositionValues(ltvData, any, any);

        assertEq(collateralValue, collateralAssets + protectedAssets, "collateralValue");
        assertEq(debtValue, debtAssets, "debtValue");
    }

    /*
    forge test -vv --mt test_SiloSolvencyLib_getPositionValues_withOracle
    */
    function test_SiloSolvencyLib_getPositionValues_withOracle() public {
        uint256 collateralAssets = 20;
        uint256 protectedAssets = 10;
        uint256 debtAssets = 3;

        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.LtvData({
            collateralOracle: ISiloOracle(COLLATERAL_ORACLE),
            debtOracle: ISiloOracle(DEBT_ORACLE),
            borrowerProtectedAssets: protectedAssets,
            borrowerCollateralAssets: collateralAssets,
            borrowerDebtAssets: debtAssets
        });

        address collateralAsset = makeAddr("collateralAsset");
        address debtAsset = makeAddr("debtAsset");

        collateralOracle.quoteMock(protectedAssets + collateralAssets, collateralAsset, 123);
        debtOracle.quoteMock(debtAssets, debtAsset, 44);

        (uint256 collateralValue, uint256 debtValue) =
            SiloSolvencyLib.getPositionValues(ltvData, collateralAsset, debtAsset);

        assertEq(collateralValue, 123, "collateralValue");
        assertEq(debtValue, 44, "debtValue");
    }
}
