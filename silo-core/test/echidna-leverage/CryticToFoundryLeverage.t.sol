// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";

// Contracts
import {SetupLeverage} from "./SetupLeverage.t.sol";
import {InvariantsLeverage} from "./InvariantsLeverage.t.sol";

// solhint-disable function-max-lines, func-name-mixedcase

/*
 * Test suite that converts from  "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract CryticToFoundryLeverage is InvariantsLeverage, SetupLeverage {
    CryticToFoundryLeverage public LeverageTester = this;

    function setUp() public {
        // Deploy protocol contracts
        _setUp();

        // Deploy actors
        _setUpActors();

        // Initialize handler contracts
        _setUpHandlers();

        vm.warp(DEFAULT_TIMESTAMP);
        vm.roll(DEFAULT_BLOCK);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 FAILING INVARIANTS REPLAY                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              FAILING POSTCONDITIONS REPLAY                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /*
    FOUNDRY_PROFILE=echidna_leverage forge test -vv --ffi --mt test_EchidnaLeverage_leverage
    */
    function test_EchidnaLeverage_leverage() public {
        LeverageTester.deposit(1, 0, 0, 0);
        LeverageTester.openLeveragePosition(4506857007, 0, RandomGenerator(1, 0, 0));
    }

    /*
    FOUNDRY_PROFILE=echidna_leverage forge test -vv --ffi --mt test_EchidnaLeverage_onFlashLoan_0
    */
    function test_EchidnaLeverage_onFlashLoan_0() public {
        LeverageTester.onFlashLoan(
            address(0x0),
            144878998102916798939665310881083899372024861808743479,
            1068209701505743703662069164166715788602248289963999918073026641719,
            "",
            RandomGenerator(0, 0, 0)
        );
    }
}
