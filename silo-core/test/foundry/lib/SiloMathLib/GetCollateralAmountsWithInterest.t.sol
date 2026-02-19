// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

// forge test -vv --mc GetCollateralAmountsWithInterestTest
contract GetCollateralAmountsWithInterestTest is Test {
    /*
    forge test -vv --mt test_getCollateralAmountsWithInterest
    */
    function test_getCollateralAmountsWithInterest() public pure {
        uint256 collateralAssets;
        uint256 debtAssets;
        uint256 rcomp;
        uint256 daoFee;
        uint256 deployerFee;

        (
            uint256 collateralAssetsWithInterest,
            uint256 debtAssetsWithInterest,
            uint256 daoAndDeployerRevenue,
            uint256 accruedInterest
        ) = SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, 0);
        assertEq(debtAssetsWithInterest, 0);
        assertEq(daoAndDeployerRevenue, 0);
        assertEq(accruedInterest, 0);

        collateralAssets = 2e18;
        debtAssets = 1e18;
        rcomp = 0.1e18;

        (collateralAssetsWithInterest, debtAssetsWithInterest, daoAndDeployerRevenue, accruedInterest) =
            SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, 2.1e18, "collateralAssetsWithInterest, just rcomp");
        assertEq(debtAssetsWithInterest, 1.1e18, "debtAssetsWithInterest, just rcomp");
        assertEq(daoAndDeployerRevenue, 0, "daoAndDeployerRevenue, just rcomp");
        assertEq(accruedInterest, 0.1e18, "accruedInterest, just rcomp");

        daoFee = 0.05e18;

        (collateralAssetsWithInterest, debtAssetsWithInterest, daoAndDeployerRevenue, accruedInterest) =
            SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, 2.095e18, "collateralAssetsWithInterest, rcomp + daoFee");
        assertEq(debtAssetsWithInterest, 1.1e18, "debtAssetsWithInterest, rcomp + daoFee");
        assertEq(daoAndDeployerRevenue, 0.005e18, "daoAndDeployerRevenue, rcomp + daoFee");
        assertEq(accruedInterest, 0.1e18, "accruedInterest, rcomp + daoFee");

        deployerFee = 0.05e18;
        daoFee = 0;

        (collateralAssetsWithInterest, debtAssetsWithInterest, daoAndDeployerRevenue, accruedInterest) =
            SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, 2.095e18, "collateralAssetsWithInterest, rcomp + deployerFee");
        assertEq(debtAssetsWithInterest, 1.1e18, "debtAssetsWithInterest, rcomp + deployerFee");
        assertEq(daoAndDeployerRevenue, 0.005e18, "daoAndDeployerRevenue, rcomp + deployerFee");
        assertEq(accruedInterest, 0.1e18, "accruedInterest, rcomp + deployerFee");

        deployerFee = 0.05e18;
        daoFee = 0.05e18;

        (collateralAssetsWithInterest, debtAssetsWithInterest, daoAndDeployerRevenue, accruedInterest) =
            SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, 2.09e18, "collateralAssetsWithInterest, rcomp + fees");
        assertEq(debtAssetsWithInterest, 1.1e18, "debtAssetsWithInterest, rcomp + fees");
        assertEq(daoAndDeployerRevenue, 0.01e18, "daoAndDeployerRevenue, rcomp + fees");
        assertEq(accruedInterest, 0.1e18, "accruedInterest, rcomp + fees");

        debtAssets = 0;

        (collateralAssetsWithInterest, debtAssetsWithInterest, daoAndDeployerRevenue, accruedInterest) =
            SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, 2e18, "collateralAssetsWithInterest - no debt, no interest");
        assertEq(debtAssetsWithInterest, 0, "debtAssetsWithInterest - no debt, no interest");
        assertEq(daoAndDeployerRevenue, 0, "daoAndDeployerRevenue - no debt, no interest");
        assertEq(accruedInterest, 0, "accruedInterest - no debt, no interest");
    }

    /*
    forge test -vv --mt test_getCollateralAmountsWithInterest_notRevert_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_getCollateralAmountsWithInterest_notRevert_fuzz(
        uint256 _collateralAssets,
        uint256 _debtAssets,
        uint256 _rcomp,
        uint64 _daoFee,
        uint64 _deployerFee
    ) public pure {
        vm.assume(uint256(_daoFee) + _deployerFee <= 1e18);
        SiloMathLib.getCollateralAmountsWithInterest(_collateralAssets, _debtAssets, _rcomp, _daoFee, _deployerFee);
    }

    /*
    forge test -vv --mt test_getCollateralAmountsWithInterest_cap
    */
    function test_getCollateralAmountsWithInterest_cap() public pure {
        uint256 collateralAssets = type(uint256).max - 1e18;
        uint256 debtAssets = type(uint128).max;
        uint256 rcomp = 0.1e18;
        uint256 daoFee = 0.1e18;
        uint256 deployerFee = 0.1e18;

        (
            uint256 collateralAssetsWithInterest,
            uint256 debtAssetsWithInterest,
            uint256 daoAndDeployerRevenue,
            uint256 accruedInterest
        ) = SiloMathLib.getCollateralAmountsWithInterest(collateralAssets, debtAssets, rcomp, daoFee, deployerFee);

        assertEq(collateralAssetsWithInterest, type(uint256).max, "collateralAssetsWithInterest");
        assertEq(debtAssetsWithInterest, debtAssets + debtAssets * rcomp / 1e18, "debtAssetsWithInterest");
        // forge-lint: disable-next-line(divide-before-multiply)
        assertEq(daoAndDeployerRevenue, (debtAssets * rcomp / 1e18) * 0.2e18 / 1e18, "daoAndDeployerRevenue");
        assertEq(accruedInterest, debtAssets * rcomp / 1e18, "accruedInterest");
    }
}
