// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SetupHookV3} from "./SetupHookV3.t.sol";
import {DefaultingHandler} from "../siloHookV2/handlers/user/DefaultingHandler.t.sol";
import {Invariants} from "silo-core/test/invariants/Invariants.t.sol";
import {DefaultBeforeAfterHooks} from "silo-core/test/invariants/hooks/DefaultBeforeAfterHooks.t.sol";
import {BaseHandlerDefaulting} from "../siloHookV2/base/BaseHandlerDefaulting.t.sol";

/*
    make echidna-leverage-assert
    make echidna-leverage
*/
/// @title HookV3Tester
/// @notice Entry point for invariant testing, inherits all contracts, invariants & handler
/// @dev Mono contract that contains all the testing logic
contract HookV3Tester is Invariants, DefaultingHandler, SetupHookV3 {
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
    }

    function _defaultHooksBefore(address silo) internal override(BaseHandlerDefaulting, DefaultBeforeAfterHooks) {
        BaseHandlerDefaulting._defaultHooksBefore(silo);
    }
}
