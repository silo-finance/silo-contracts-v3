// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";

// Contracts
import {SetupHookV3} from "./SetupHookV3.t.sol";
import {DefaultingHandler} from "../siloHookV2/handlers/user/DefaultingHandler.t.sol";
import {Invariants} from "silo-core/test/invariants/Invariants.t.sol";
import {DefaultBeforeAfterHooks} from "silo-core/test/invariants/hooks/DefaultBeforeAfterHooks.t.sol";
import {BaseHandlerDefaulting} from "../siloHookV2/base/BaseHandlerDefaulting.t.sol";

// solhint-disable function-max-lines, func-name-mixedcase

/*
 * Test suite that converts from  "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract CryticToFoundryHookV3 is Invariants, DefaultingHandler, SetupHookV3 {
    CryticToFoundryHookV3 public DefaultingTester = this;

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
    FOUNDRY_PROFILE=echidna_hookV3 forge test -vv --ffi --mt test_EchidnaDefaulting_empty
    */
    function test_EchidnaDefaulting_empty() public {
        // DefaultingTester.deposit(1, 0, 0, 0);
        // DefaultingTester.openDefaultingPosition(4506857007, 0, RandomGenerator(1, 0, 0));
    }

    function _defaultHooksBefore(address silo) internal override(BaseHandlerDefaulting, DefaultBeforeAfterHooks) {
        BaseHandlerDefaulting._defaultHooksBefore(silo);
    }
}
