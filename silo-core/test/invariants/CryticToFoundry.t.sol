// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// Contracts
import {Invariants} from "./Invariants.t.sol";
import {Setup} from "./Setup.t.sol";
import {ISiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {MockSiloOracle} from "./utils/mocks/MockSiloOracle.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/*
 * Test suite that converts from  "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract CryticToFoundry is Invariants, Setup {
    CryticToFoundry Tester = this;

    function setUp() public {
        // Deploy protocol contracts
        _setUp();

        // Deploy actors
        _setUpActors();

        // Initialize handler contracts
        _setUpHandlers();

        /// @dev fixes the actor to the first user
        actor = actors[USER1];

        vm.warp(DEFAULT_TIMESTAMP);
        vm.roll(DEFAULT_BLOCK);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 FAILING INVARIANTS REPLAY                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              FAILING POSTCONDITIONS REPLAY                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     INVARIANTS REPLAY                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_replayechidna_BASE_INVARIANT1
    */
    function test_replayechidna_BASE_INVARIANT1() public {
        Tester.setOraclePrice(154174253363420274135519693994558375770505353341038094319633, 1);
        Tester.setOraclePrice(117361312846819359113791019924540616345894207664659799350103, 0);
        Tester.mint(1025, 0, 1, 0);
        Tester.deposit(1, 0, 0, 1);
        Tester.borrowShares(1, 0, 0);
        echidna_BASE_INVARIANT();
        Tester.setOraclePrice(1, 1);
        echidna_BASE_INVARIANT();
    }

    // FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_replayechidna_LENDING_INVARIANT
    function test_replayechidna_LENDING_INVARIANT() public {
        Tester.deposit(1, 0, 0, 1);
        //        echidna_LENDING_INVARIANT();
    }

    function test_replayechidna_BORROWING_INVARIANT2() public {
        Tester.mint(1, 0, 0, 1);
        Tester.deposit(1, 0, 0, 1);
        Tester.assert_LENDING_INVARIANT_B(0, 1);
        echidna_BORROWING_INVARIANT();
    }

    function test_replayechidna_BASE_INVARIANT2() public {
        Tester.mint(1, 0, 1, 1);
        Tester.deposit(1, 0, 1, 1);
        Tester.assert_LENDING_INVARIANT_B(1, 1);
        echidna_BASE_INVARIANT();
    }

    function test_echidna_BORROWING_INVARIANT() public {
        _setUpActorAndDelay(USER2, 203047);
        this.setOraclePrice(75638385906155076883289831498661502101511673487426594778361149796941034811732, 64);
        _setUpActorAndDelay(USER1, 3032);
        this.deposit(77844067395127635960841998878023, 20, 55, 57);
        _setUpActorAndDelay(USER1, 86347);
        this.deposit(774, 25, 0, 211);
        _setUpActorAndDelay(USER2, 114541);
        this.assertBORROWING_HSPOST_F(211, 8);
        _setUpActorAndDelay(USER1, 487078);
        this.setOraclePrice(115792089237316195423570985008687907853269984665640562830531764393283954933761, 0);
        echidna_BORROWING_INVARIANT();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POSTCONDITIONS REPLAY                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_withdrawEchidna() public {
        Tester.mint(261704911235117686095, 3, 22, 5);
        Tester.setOraclePrice(5733904121326457137913237185177414188002932016538715575300939815758706, 1);
        Tester.mint(315177161663537856181160994225, 0, 1, 3);
        Tester.borrowShares(1, 0, 0);
        Tester.setOraclePrice(5735839262457902375842327974553553747246352514262698977554375720302080, 0);
        Tester.withdraw(1238665, 0, 0, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_depositEchidna
    */
    function test_depositEchidna() public {
        Tester.deposit(1, 0, 0, 0);
    }

    function test_flashLoanEchidna() public {
        Tester.flashLoan(1, 76996216303583, 0, 0);
    }

    function test_transitionCollateralEchidna() public {
        Tester.transitionCollateral(0, RandomGenerator(0, 0, 0));
    }

    function test_liquidationCallEchidna() public {
        Tester.mint(10402685166958480039898380057, 0, 0, 1);
        Tester.deposit(1, 0, 1, 1);
        Tester.setOraclePrice(32922152482718336970808482575712338131227045040770117410308, 1);
        Tester.borrowShares(1, 0, 0);
        Tester.setOraclePrice(1, 1);
        Tester.liquidationCall(
            1179245955276247436741786656479833618730492640882500598892, false, RandomGenerator(0, 0, 1)
        );
    }

    function test_replaytransitionCollateral() public {
        Tester.mint(1023, 0, 0, 0);
        Tester.transitionCollateral(679, RandomGenerator(0, 0, 0));
    }

    function test_replaytransitionCollateral2() public {
        Tester.mint(4003, 0, 0, 0);
        Tester.mint(4142174, 0, 1, 1);
        Tester.setOraclePrice(5167899937944767889217962943343171205019348763, 0);
        Tester.assertBORROWING_HSPOST_F(0, 1);
        Tester.setOraclePrice(2070693789985146455311434266782705402030751026, 1);
        Tester.transitionCollateral(2194, RandomGenerator(0, 0, 0));
    }

    function test_replayTesterassertBORROWING_HSPOST_F2() public {
        Tester.mint(40422285801235863700109, 1, 1, 0); // Deposit on Silo 1 for ACTOR2
        Tester.deposit(2, 0, 0, 1); // Deposit on Silo 0 for ACTOR1
        Tester.assertBORROWING_HSPOST_F(1, 0); // ACTOR tries to maxBorrow on Silo 0
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 POSTCONDITIONS: FINAL REVISION                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_replay_deposit() public {
        Tester.mint(13030923723425133684497, 0, 0, 0);
        Tester.deposit(21991861, 13, 59, 3);
        Tester.borrow(621040, 0, 1);
        _delay(11818);
        Tester.accrueInterestForBothSilos();
        _delay(3706);
        Tester.deposit(7866581, 0, 1, 1);
    }

    function test_replay_borrow() public {
        Tester.mint(2518531959823837031380, 0, 0, 0);
        Tester.deposit(1780157, 0, 1, 1);
        Tester.borrow(1722365, 0, 1);
        _delay(29);
        Tester.accrueInterestForBothSilos();
        _delay(22);
        Tester.borrow(1, 0, 1);
    }

    function test_replay_assertBORROWING_HSPOST_F() public {
        Tester.mint(11638058238813243150339, 0, 0, 0);
        Tester.deposit(8533010, 0, 1, 1);
        Tester.borrow(8256930, 0, 1);
        _delay(12);
        Tester.accrueInterest(1);
        _delay(7);
        Tester.assertBORROWING_HSPOST_F(0, 1);
    }

    function test_replay_accrueInterestForSilo() public {
        Tester.mint(157818656604306680780, 0, 0, 0);
        Tester.deposit(252962, 0, 1, 1);
        Tester.borrow(94940, 0, 1);
        _delay(12243);
        Tester.deposit(1, 0, 1, 0);
        _delay(95151);
        Tester.accrueInterestForSilo(1);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Fast forward the time and set up an actor,
    /// @dev Use for ECHIDNA call-traces
    function _delay(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up an actor
    function _setUpActor(address _origin) internal {
        actor = actors[_origin];
    }

    /// @notice Set up an actor and fast forward the time
    /// @dev Use for ECHIDNA call-traces
    function _setUpActorAndDelay(address _origin, uint256 _seconds) internal {
        actor = actors[_origin];
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up a specific block and actor
    function _setUpBlockAndActor(uint256 _block, address _user) internal {
        vm.roll(_block);
        actor = actors[_user];
    }

    /// @notice Set up a specific timestamp and actor
    function _setUpTimestampAndActor(uint256 _timestamp, address _user) internal {
        vm.warp(_timestamp);
        actor = actors[_user];
    }
}
