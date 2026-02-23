// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

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
}
