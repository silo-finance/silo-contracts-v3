// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math, SiloMathLib, Rounding} from "silo-core/contracts/lib/SiloMathLib.sol";

// forge test -vv --mc GetDebtAmountsWithInterestTest
contract GetDebtAmountsWithInterestTest is Test {
    using Math for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    /*
    forge test -vv --mt test_getDebtAmountsWithInterest_pass
    */
    function test_getDebtAmountsWithInterest_pass() public pure {
        uint256 debtAssets;
        uint256 rcompInDp;

        (uint256 debtAssetsWithInterest, uint256 accruedInterest) =
            SiloMathLib.getDebtAmountsWithInterest(debtAssets, rcompInDp);

        assertEq(debtAssetsWithInterest, 0);
        assertEq(accruedInterest, 0);

        rcompInDp = 0.1e18;

        (debtAssetsWithInterest, accruedInterest) = SiloMathLib.getDebtAmountsWithInterest(debtAssets, rcompInDp);

        assertEq(debtAssetsWithInterest, 0, "debtAssetsWithInterest, just rcomp");
        assertEq(accruedInterest, 0, "accruedInterest, just rcomp");

        debtAssets = 1e18;

        (debtAssetsWithInterest, accruedInterest) = SiloMathLib.getDebtAmountsWithInterest(debtAssets, rcompInDp);

        assertEq(debtAssetsWithInterest, 1.1e18, "debtAssetsWithInterest - no debt, no interest");
        assertEq(accruedInterest, 0.1e18, "accruedInterest - no debt, no interest");
    }

    /*
    forge test -vv --mt test_getDebtAmountsWithInterest_notRevert
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_getDebtAmountsWithInterest_notRevert_fuzz(uint256 _debtAssets, uint256 _rcompInDp) public pure {
        SiloMathLib.getDebtAmountsWithInterest(_debtAssets, _rcompInDp);
    }

    /*
    forge test -vv --mt test_getDebtAmountsWithInterest_accruedInterest_overflow
    */
    function test_getDebtAmountsWithInterest_accruedInterest_overflow() public pure {
        uint256 debtAssets = type(uint248).max;
        // this should be impossible because of IRM cap, but for QA we have to support it
        uint256 rcompInDp = 1e18; // 100 %

        (uint256 debtAssetsWithInterest, uint256 accruedInterest) =
            SiloMathLib.getDebtAmountsWithInterest(debtAssets, rcompInDp);

        uint256 interestWithoutOverflow =
            debtAssets.mulDiv(rcompInDp, _PRECISION_DECIMALS, Rounding.ACCRUED_INTEREST);

        assertGt(interestWithoutOverflow, accruedInterest, "accruedInterest is lower on overflow");
        assertEq(debtAssetsWithInterest, debtAssets + accruedInterest, "No debt assets overflow");
    }

    /*
    forge test -vv --mt test_getDebtAmountsWithInterest_interest_overflow
    */
    function test_getDebtAmountsWithInterest_interest_overflow() public pure {
        uint256 debtAssets = type(uint256).max;
        // this should be impossible because of IRM cap, but for QA we have to support it
        uint256 rcompInDp = 1e18; // 100 %

        (uint256 debtAssetsWithInterest, uint256 accruedInterest) =
            SiloMathLib.getDebtAmountsWithInterest(debtAssets, rcompInDp);

        assertEq(debtAssetsWithInterest, debtAssets, "debtAssets stay the same");
        assertEq(accruedInterest, 0, "accruedInterest is zero");
    }
}
