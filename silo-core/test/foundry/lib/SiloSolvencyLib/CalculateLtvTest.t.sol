// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "openzeppelin5/utils/math/Math.sol";

import {Test} from "forge-std/Test.sol";
import {SiloSolvencyLib, ISiloOracle} from "silo-core/contracts/lib/SiloSolvencyLib.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";

import {OraclesHelper} from "../../_common/OraclesHelper.sol";

/*
forge test -vv --mc CalculateLtvTest
*/
contract CalculateLtvTest is Test, OraclesHelper {
    uint256 internal constant DECIMALS_POINTS = 1e18;

    /*
    forge test -vv --mt test_SiloSolvencyLib_calculateLtv_noOracle_zero
    */
    function test_SiloSolvencyLib_calculateLtv_noOracle_zero() public view {
        uint128 zero;

        ISiloOracle noOracle;

        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.LtvData(noOracle, noOracle, zero, zero, zero);

        address any = address(1);

        (,, uint256 ltv) = SiloSolvencyLib.calculateLtv(ltvData, any, any);

        assertEq(ltv, 0, "no debt no collateral");
    }

    /*
    forge test -vv --mt test_SiloSolvencyLib_calculateLtv_noOracle_infinity
    */
    function test_SiloSolvencyLib_calculateLtv_noOracle_infinity() public view {
        uint128 zero;
        uint128 debtAssets = 1;

        ISiloOracle noOracle;

        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.LtvData(noOracle, noOracle, zero, zero, debtAssets);

        address any = address(1);

        (,, uint256 ltv) = SiloSolvencyLib.calculateLtv(ltvData, any, any);

        assertEq(ltv, SiloSolvencyLib._INFINITY, "when only debt");
    }

    /*
    forge test -vv --mt test_SiloSolvencyLib_calculateLtv_noOracle_fuzz
    */
    function test_SiloSolvencyLib_calculateLtv_noOracle_fuzz(
        uint128 _collateralAssets,
        uint128 _protectedAssets,
        uint128 _debtAssets
    ) public view {
        ISiloOracle noOracle;
        uint256 sumOfCollateralAssets = uint256(_collateralAssets) + _protectedAssets;
        // because this is the same token, we assume the sum can not be higher than uint128
        vm.assume(sumOfCollateralAssets < type(uint256).max / DECIMALS_POINTS);

        SiloSolvencyLib.LtvData memory ltvData =
            SiloSolvencyLib.LtvData(noOracle, noOracle, _collateralAssets, _protectedAssets, _debtAssets);

        address any = address(1);

        (,, uint256 ltv) = SiloSolvencyLib.calculateLtv(ltvData, any, any);

        uint256 expectedLtv;

        if (sumOfCollateralAssets == 0 && _debtAssets == 0) {
            // expectedLtv is 0;
        } else if (sumOfCollateralAssets == 0) {
            expectedLtv = SiloSolvencyLib._INFINITY;
        } else {
            expectedLtv =
                Math.mulDiv(_debtAssets, DECIMALS_POINTS, sumOfCollateralAssets, Math.Rounding(Rounding.LTV));
        }

        assertEq(ltv, expectedLtv, "ltv");
    }

    /*
    forge test -vv --mt test_SiloSolvencyLib_calculateLtv_constant
    */
    function test_SiloSolvencyLib_calculateLtv_constant(
        uint128 _collateralAssets,
        uint128 _protectedAssets,
        uint128 _debtAssets
    ) public {
        vm.assume(_debtAssets != 0);
        uint256 sumOfCollateralAssets = uint256(_collateralAssets) + _protectedAssets;
        // because this is the same token, we assume the sum can not be higher than uint256
        vm.assume(sumOfCollateralAssets < type(uint256).max / DECIMALS_POINTS);
        vm.assume(sumOfCollateralAssets != 0);

        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.LtvData(
            ISiloOracle(COLLATERAL_ORACLE),
            ISiloOracle(DEBT_ORACLE),
            _protectedAssets,
            _collateralAssets,
            _debtAssets
        );

        uint256 collateralSum = ltvData.borrowerCollateralAssets + ltvData.borrowerProtectedAssets;
        collateralOracle.quoteMock(collateralSum, COLLATERAL_ASSET, 9999);
        debtOracle.quoteMock(ltvData.borrowerDebtAssets, DEBT_ASSET, 1111);

        (,, uint256 ltv) = SiloSolvencyLib.calculateLtv(ltvData, COLLATERAL_ASSET, DEBT_ASSET);

        assertEq(
            ltv,
            Math.mulDiv(1111, DECIMALS_POINTS, 9999, Math.Rounding(Rounding.LTV)),
            "constant values, constant ltv"
        );
    }
}
