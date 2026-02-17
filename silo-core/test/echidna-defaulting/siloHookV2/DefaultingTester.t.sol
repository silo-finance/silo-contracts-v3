// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Invariants} from "silo-core/test/invariants/Invariants.t.sol";
import {DefaultingHandler} from "./handlers/user/DefaultingHandler.t.sol";
import {SetupDefaulting} from "./SetupDefaulting.t.sol";
import {BaseHandlerDefaulting} from "./base/BaseHandlerDefaulting.t.sol";
import {DefaultBeforeAfterHooks} from "silo-core/test/invariants/hooks/DefaultBeforeAfterHooks.t.sol";

/*
    make echidna-leverage-assert
    make echidna-leverage
*/
/// @title DefaultingTester
/// @notice Entry point for invariant testing, inherits all contracts, invariants & handler
/// @dev Mono contract that contains all the testing logic
contract DefaultingTester is Invariants, DefaultingHandler, SetupDefaulting {
    constructor() payable {
        // Deploy protocol contracts and protocol actors
        setUp();
    }

    /// @dev Foundry compatibility faster setup debugging
    function setUp() internal {
        // Deploy protocol contracts and protocol actors
        _setUp();

        // Deploy actors
        _setUpActors();

        // Initialize handler contracts
        _setUpHandlers();

        vm.warp(DEFAULT_TIMESTAMP);
        vm.roll(DEFAULT_BLOCK);
    }

    function _defaultHooksBefore(address silo) internal override(BaseHandlerDefaulting, DefaultBeforeAfterHooks) {
        BaseHandlerDefaulting._defaultHooksBefore(silo);
    }
}
