// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloLendingLib} from "silo-core/contracts/lib/SiloLendingLib.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";

/*
   FOUNDRY_PROFILE=core-test forge test -vv --mc ApplyFraction
*/
contract ApplyFraction is Test {
    /*
    FOUNDRY_PROFILE=core-test forge test -vv --mt test_applyFractions_overflow
    */
    function test_applyFractions_overflow() public {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        $.totalAssets[ISilo.AssetType.Collateral] = type(uint256).max;

        ISilo.Fractions memory fractions = $.fractions;

        fractions.interest = 999999999999999990;
        fractions.revenue = 1000;

        $.fractions = fractions;

        // ensure we don't revert
        SiloLendingLib.applyFractions({
            _totalDebtAssets: 1,
            _rcomp: 20,
            _accruedInterest: 1000,
            _fees: 20,
            _totalFees: 1000
        });
    }
    
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_applyFractions_debug
    */
    function test_applyFractions_debug() public {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        // Integer interest A already computed in getCollateralAmountsWithInterest.
        // Integer fee is mulDiv(A, fees) = 9 * 10% = 0.
        uint256 accruedInterestA = 9;
        uint256 fees = 0.1e18;
        uint256 totalFeesFromIntegerPath = accruedInterestA * fees / 1e18;

        // Collateral must not be 0 or type(uint256).max — those early-return and skip fractions.
        $.totalAssets[ISilo.AssetType.Collateral] = 1_000 + accruedInterestA - totalFeesFromIntegerPath;
        $.totalAssets[ISilo.AssetType.Debt] = 1 + accruedInterestA;

        // Force integralInterest = 1: remainder(1 * 1) + (1e18 - 1) overflows 1e18.
        ISilo.Fractions memory fractions = $.fractions;
        fractions.interest = 1e18 - 1;
        fractions.revenue = 0;
        $.fractions = fractions;

        (uint256 accruedInterest, uint256 totalFees) = SiloLendingLib.applyFractions({
            _totalDebtAssets: 1,
            _rcomp: 1,
            _accruedInterest: accruedInterestA,
            _fees: fees,
            _totalFees: totalFeesFromIntegerPath
        });

        uint256 expectedFeesOnFullInterest = accruedInterest * fees / 1e18;

        // #region agent log
        console2.log({p0: "accruedInterestA", p1: accruedInterestA});
        console2.log({p0: "totalFeesFromIntegerPath", p1: totalFeesFromIntegerPath});
        console2.log({p0: "accruedInterest after applyFractions", p1: accruedInterest});
        console2.log({p0: "post-fix totalFees after applyFractions", p1: totalFees});
        console2.log({p0: "post-fix expectedFeesOnFullInterest", p1: expectedFeesOnFullInterest});
        console2.log({p0: "post-fix revenueFraction", p1: uint256($.fractions.revenue)});
        // #endregion

        assertEq({left: totalFeesFromIntegerPath, right: 0, err: "integer fee on A=9 truncates to 0"});
        assertEq({left: accruedInterest, right: 10, err: "A + integralInterest"});
        assertEq({left: expectedFeesOnFullInterest, right: 1, err: "10 * 10% is an exact 1 wei fee"});
        assertEq({left: $.fractions.revenue, right: 0, err: "fee remainder consumed into integral revenue"});
        assertEq({
            left: totalFees,
            right: expectedFeesOnFullInterest,
            err: "fee on A+I credited via fraction overflow"
        });
    }
}
