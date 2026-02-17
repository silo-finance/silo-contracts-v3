// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloIncentivesControllerCompatible} from
    "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";

// Contracts
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {
    IInterestRateModelV2, InterestRateModelV2
} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";

// Test Contracts

// Mock Contracts
import {TestERC20} from "silo-core/test/invariants/utils/mocks/TestERC20.sol";
import {TestWETH} from "silo-core/test/echidna-leverage/utils/mocks/TestWETH.sol";

// Interfaces
import {Setup} from "silo-core/test/invariants/Setup.t.sol";
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract SetupDefaulting is Setup {
    function _initHook() internal virtual override {
        super._initHook();
        _createIncentiveController();
    }

    function _hookImplementation() internal virtual override returns (address hook) {
        hook = address(new SiloHookV2());
    }

    function _createIncentiveController() internal {
        gauge = new SiloIncentivesControllerCompatible(address(this), address(liquidationModule), address(vault1));

        address owner = Ownable(address(liquidationModule)).owner();
        vm.prank(owner);
        IGaugeHookReceiver(address(liquidationModule)).setGauge(gauge, IShareToken(address(vault1)));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          SETUP FUNCTIONS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployAssets() internal override {
        console2.log("/SetupDefaulting._deployAssets/");
        _asset0 = TestERC20(address(new TestWETH("Test Token0", "TT0", 18)));
        _asset1 = new TestERC20("Test Token1", "TT1", 6);
        baseAssets.push(address(_asset0));
        baseAssets.push(address(_asset1));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTOR SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal override {
        console2.log("/SetupDefaulting._setUpActors/");
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

        address[] memory contracts = new address[](3);
        contracts[0] = address(_vault0);
        contracts[1] = address(_vault1);
        contracts[2] = address(liquidationModule);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, contracts);

            // Mint initial balances to actors
            for (uint256 j = 0; j < underlyingAssetsLength; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }

            actorAddresses.push(_actor);
        }

        console2.log("/SetupDefaulting._setUpActors/ done");
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
        Actor _actor = new Actor(tokens, contracts);
        actors[userAddress] = Actor(_actor);
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }

    function _siloInitDataIdentifier() internal pure virtual override returns (string memory) {
        return "HOOK_V2";
    }

    function _initData(address mock0, address mock1) internal override {
        super._initData(mock0, mock1);

        siloData["HOOK_V2"] = ISiloConfig.InitData({
            deployer: address(this),
            daoFee: 0.15e18,
            deployerFee: 0.1e18,
            token0: mock0,
            solvencyOracle0: address(0),
            maxLtvOracle0: address(0),
            interestRateModel0: address(interestRateModelV2),
            maxLtv0: 0.75e18,
            lt0: 0.85e18,
            liquidationTargetLtv0: 0.76e18,
            liquidationFee0: 0.05e18,
            flashloanFee0: 0.01e18,
            callBeforeQuote0: false,
            hookReceiver: address(liquidationModule),
            token1: mock1,
            solvencyOracle1: address(0),
            maxLtvOracle1: address(0),
            interestRateModel1: address(interestRateModelV2),
            maxLtv1: 0,
            lt1: 0,
            liquidationTargetLtv1: 0,
            liquidationFee1: 0,
            flashloanFee1: 0.01e18,
            callBeforeQuote1: false
        });
    }
}
