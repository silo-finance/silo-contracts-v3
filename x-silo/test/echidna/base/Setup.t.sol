// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

// Contracts
import {XSilo} from "x-silo/contracts/XSilo.sol";
import {Stream} from "x-silo/contracts/modules/Stream.sol";

// Utils
import {Actor} from "../utils/Actor.sol";

// Test Contracts
import {BaseTest} from "./BaseTest.t.sol";

// Mock Contracts
import {TestERC20} from "silo-core/test/invariants/utils/mocks/TestERC20.sol";


/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp() internal {
        // Deploy assets
        _deployAssets();

        // Deploy XSilos
        _deployXSilos();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          SETUP FUNCTIONS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployAssets() internal {
        siloToken = address(new TestERC20("Silo Token", "SILO", 18));
    }

    function _deployXSilos() internal {
        // Calculate contract addresses that will be created
        xSilo = new XSilo(address(this), siloToken, address(0));
        stream = new Stream(address(this), address(xSilo));
        xSilo.setStream(stream);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTOR SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal {
        // Initialize the three actors of the fuzzers
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        // Initialize the tokens array
        address[] memory tokens = new address[](1);
        tokens[0] = address(siloToken);

        address[] memory contracts = new address[](2);
        contracts[0] = address(xSilo);
        contracts[1] = address(stream);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, contracts);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }

            actorAddresses.push(_actor);
        }
    }

    /// @notice Deploy an actor proxy contract for a user address
    /// @param userAddress Address of the user
    /// @param tokens Array of token addresses
    /// @param contracts Array of contract addresses to aprove tokens to
    /// @return actorAddress Address of the deployed actor
    function _setUpActor(address userAddress, address[] memory tokens, address[] memory contracts)
        internal
        returns (address actorAddress)
    {
        bool success;
        Actor _actor = new Actor(tokens, contracts);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }
}
