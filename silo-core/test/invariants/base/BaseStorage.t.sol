// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {Silo} from "silo-core/contracts/Silo.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";

// Mock Contracts
import {TestERC20} from "../utils/mocks/TestERC20.sol";

// Test Contracts

// Utils
import {Actor} from "../utils/Actor.sol";

// Interfaces
import {ISiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interestRateModel/InterestRateModelV2Config.sol";
import {IInterestRateModelV2Factory} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {ISiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {SwapRouterMock} from "silo-core/test/foundry/leverage/mocks/SwapRouterMock.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

/// @notice BaseStorage contract for all test contracts, works in tandem with BaseTest
abstract contract BaseStorage {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    uint256 public constant DEFAULT_TIMESTAMP = 337812;
    uint256 public constant DEFAULT_BLOCK = 4239;

    uint256 constant MAX_TOKEN_AMOUNT = 1e29;

    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_MONTH = ONE_YEAR / 12;
    uint256 constant ONE_YEAR = 365 days;

    uint256 internal constant NUMBER_OF_ACTORS = 3;
    uint256 internal constant INITIAL_ETH_BALANCE = 1e26;
    uint256 internal constant INITIAL_COLL_BALANCE = 1e21;

    address internal constant QUOTE_TOKEN_ADDRESS = address(0xdead);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTORS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Stores the actor during a handler call
    Actor internal actor;

    /// @notice Mapping of fuzzer user addresses to actors
    mapping(address => Actor) internal actors;

    /// @notice used for defalting - stores rewards balance before defaulting liquidation
    mapping(address user => uint256 gaugeBalance) rewardsBalanceBefore;

    /// @notice Array of all actor addresses
    address[] internal actorAddresses;

    /// @notice The pool admin is set to this contract, the Tester contract
    address internal poolAdmin = address(this);

    /// @notice The actor to which hooks are applied to
    address internal targetActor;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              SUITE STORAGE: PROTOCOL CONTRACTS                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice The two silos of a market
    address internal _vault0;
    address internal _vault1;
    Silo internal vault0;
    Silo internal vault1;

    /// @notice Protocol factories
    ISiloFactory siloFactory;
    IInterestRateModelV2Factory interestRateModelV2ConfigFactory;

    /// @notice silo Config
    ISiloConfig internal siloConfig;

    /// @notice The interest rate model for the market
    IInterestRateModelV2 interestRateModelV2;

    /// @notice Secondary contracts
    ISiloDeployer siloDeployer;
    PartialLiquidation liquidationModule;
    LeverageRouter leverageRouter;
    // PartialLiquidationByDefaulting liquidationByDefaultingModule;
    SwapRouterMock swapRouterMock;
    ISiloIncentivesController gauge;
    SiloLens siloLens;

    /// @notice Implementations
    address siloImpl;
    address shareProtectedCollateralTokenImpl;
    address shareDebtTokenImpl;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     SUITE STORAGE: ASSETS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Suite base assets
    TestERC20 internal _asset0;
    TestERC20 internal _asset1;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     SUITE STORAGE: MOCKS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Mock oracles
    address internal oracle0;
    address internal oracle1;

    /// @notice Mock flashloan receiver for echidna
    address internal flashLoanReceiver;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EXTRA VARIABLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Array of base assets for the suite
    address[] internal baseAssets;

    /// @notice Array of silos for the suite
    address[] internal silos;

    /// @notice Array of share tokens for the suite
    address[] internal shareTokens;

    /// @notice Array of debt tokens for the suite
    address[] internal debtTokens;

    /// @notice Array of prototected collaterals share tokens for the suite
    address[] internal protectedTokens;

    // Data

    /// @notice IRM configs
    IInterestRateModelV2.Config[] presetIRMConfigs;
    mapping(string IRMConfigName => address IRMConfigAddress) internal IRMConfigs;

    /// @notice Mapping of silo init data
    mapping(string identifier => ISiloConfig.InitData siloInitData) internal siloData;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          STRUCTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
