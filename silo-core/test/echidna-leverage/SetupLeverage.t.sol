// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Utils
import {ActorLeverage} from "./utils/ActorLeverage.sol";

// Contracts
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {
    IInterestRateModelV2,
    InterestRateModelV2
} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {SwapRouterMock} from "silo-core/test/foundry/leverage/mocks/SwapRouterMock.sol";

// Test Contracts

// Mock Contracts
import {TestERC20} from "silo-core/test/invariants/utils/mocks/TestERC20.sol";
import {TestWETH} from "./utils/mocks/TestWETH.sol";

// Interfaces
import {Setup} from "silo-core/test/invariants/Setup.t.sol";
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";

import {console} from "forge-std/console.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract SetupLeverage is Setup {
    function _setUp() internal override {
        super._setUp();

        _deployLeverage();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          SETUP FUNCTIONS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployAssets() internal override {
        _asset0 = TestERC20(address(new TestWETH("Test Token0", "TT0", 18)));
        _asset1 = new TestERC20("Test Token1", "TT1", 6);
        baseAssets.push(address(_asset0));
        baseAssets.push(address(_asset1));
    }

    function _deployLeverage() internal {
        leverageRouter = new LeverageRouter(address(this), address(this), address(_asset0));
        leverageRouter.setRevenueReceiver(address(0xDA0));

        swapRouterMock = new SwapRouterMock();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTOR SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal override {
        // Initialize the three actors of the fuzzers
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        uint256 underlyingAssetsLength = 2;

        // Initialize the tokens array
        address[] memory tokens = new address[](underlyingAssetsLength + 6);
        tokens[0] = address(_asset0);
        tokens[1] = address(_asset1);

        // share tokens array
        (tokens[2], tokens[3], tokens[4]) = vault0.config().getShareTokens(_vault0);
        (tokens[5], tokens[6], tokens[7]) = vault0.config().getShareTokens(_vault1);

        address[] memory contracts = new address[](5);
        contracts[0] = address(_vault0);
        contracts[1] = address(_vault1);
        contracts[2] = address(liquidationModule);
        contracts[3] = address(leverageRouter);
        contracts[4] = address(swapRouterMock);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, contracts);
            ActorLeverage(payable(_actor)).initLeverageApprovals(tokens[4], leverageRouter);
            ActorLeverage(payable(_actor)).initLeverageApprovals(tokens[7], leverageRouter);

            // Mint initial balances to actors
            for (uint256 j = 0; j < underlyingAssetsLength; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }

            actorAddresses.push(_actor);
        }

        // set first actor an admin for leverare router
        leverageRouter.grantRole(bytes32(0), actorAddresses[0]);
        // set first actor an pauser for leverare router
        leverageRouter.grantRole(leverageRouter.PAUSER_ROLE(), actorAddresses[0]);
    }

    /// @notice Deploy an actor proxy contract for a user address
    /// @param userAddress Address of the user
    /// @param tokens Array of token addresses
    /// @param contracts Array of contract addresses to aprove tokens to
    /// @return actorAddress Address of the deployed actor
    function _setUpActor(address userAddress, address[] memory tokens, address[] memory contracts)
        internal
        override
        returns (address actorAddress)
    {
        bool success;
        ActorLeverage _actor = new ActorLeverage(tokens, contracts);
        actors[userAddress] = Actor(_actor);
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }
}
