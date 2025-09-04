// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {DynamicKinkModelHandlers} from "silo-core/test/echidna-dkink-irm/DynamicKinkModelHandlers.t.sol";
import {Invariants} from "silo-core/test/echidna-dkink-irm/invariants/Invariants.t.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {DynamicKinkModelFactory} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";

/*
 * Test suite that converts from "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract KinkCryticToFoundry is DynamicKinkModelHandlers, Invariants, Test {
    KinkCryticToFoundry DynamicKinkModelTester = this;
    uint256 constant DEFAULT_TIMESTAMP = 337812;

    function setUp() public {
        _deploySiloMock();
        _deployDynamicKinkModel();

        _siloMock.setIRM(IInterestRateModel(address(_irm)));

        vm.warp(DEFAULT_TIMESTAMP);
    }

    /*
    Template for creating test cases from echidna output:
    
    FOUNDRY_PROFILE=echidna_dkink forge test -vv --ffi --mt test_example_template
    */
    function test_example_template() public {
        // Example: Deploy IRM with specific config
        updateConfig({
            _ulow: 0.8e18,
            _u1: 0.85e18,
            _u2: 0.9e18,
            _ucrit: 0.95e18,
            _rmin: 0.01e18,
            _kmin: 0.05e18,
            _kmax: 1e18,
            _alpha: 0.01e18,
            _cminus: 0.01e18,
            _cplus: 0.02e18,
            _c1: 0.85e18,
            // _c2: 0.9e18,
            _dmax: 0.1e18
        });
    }

    /*
    FOUNDRY_PROFILE=echidna_dkink forge test --ffi --mt test_assert_when_u_grow_rcur_grow_currentView -vv
    */
    function test_assert_when_u_grow_rcur_grow_currentView() public {
    DynamicKinkModelTester.deposit(1000);
        DynamicKinkModelTester.updateConfig(1,-2025996727877639,424763659653313480024366434579089374176464384493916428503026809,908250818454612763806236523280888838057515780032293719315334,0,29,5214973493986630,-7899082,30192340638214399832864400440145051672109783856708946583359,4498117513107858973140970058572706515028211735065484435168599460,-1117642,0);
        DynamicKinkModelTester.deposit(377033243192396427);
        DynamicKinkModelTester.borrow(130216351404093119);
        DynamicKinkModelTester.repay(206202823744457);
        // *wait* Time delay: 1 seconds Block delay: 1
        vm.warp(block.timestamp + 1);
        console2.log("warp 1 second");
        DynamicKinkModelTester.borrow(0);
        DynamicKinkModelTester.assert_when_u_grow_rcur_grow_afterAction();
    }
}
