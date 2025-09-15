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
        DynamicKinkModelTester.updateConfig(
            1578344875583636840500282097257509158319222114120208257982354221,
            0,
            0,
            12401378665876918645239146263297710966752445026064384641373,
            0,
            0,
            91265095309,
            3227325730881796884736364887495782059947966745715537417,
            1379187928990996679687563193151466346938446557339632117973040,
            371,
            0,
            411790415206515195603089736544816073790749537851092154571057
        );
        DynamicKinkModelTester.deposit(1646464699377368395565320967192);
        DynamicKinkModelTester.borrow(1030847774571248921021596591386);
        // *wait* Time delay: 14 seconds Block delay: 1
        vm.warp(block.timestamp + 14);
        console2.log("\n\twarp 14 seconds\n");
        DynamicKinkModelTester.repay(0);
        DynamicKinkModelTester.updateConfig(
            657936294114081375866951231940763855103447264643328518055794969000112,
            0,
            596819157147565236544796529611786310649260333914943646527178536326478790,
            1590748331213702710462690056263173784353011151581933308685748045823376953,
            0,
            118,
            2655193719920,
            231020911405547252560606082653870304035805215385674185269330848783339684,
            -1303225597778002995835437500380287682970963882556615834123302854040656798,
            -24767636344,
            260891071181526763569974216277500993049263690472832840656124235192584,
            0
        );
        // *wait* Time delay: 8 seconds Block delay: 115
        vm.warp(block.timestamp + 8);
        console2.log("\n\twarp 8 seconds\n");
        DynamicKinkModelTester.deposit(13098852791534481);
        DynamicKinkModelTester.printJsonTestCase();
        DynamicKinkModelTester.assert_when_u_grow_rcur_grow_afterAction();
    }

    /*
    FOUNDRY_PROFILE=echidna_dkink forge test --mt test_when_u_decrease_rcur_decrease_afterAction -vv
    */
    function test_when_u_decrease_rcur_decrease_afterAction() public {
        DynamicKinkModelTester.updateConfig(0,197477,0,90550723188720075509816904424820626146164564409726574988720,8982233115046020707826570672201292843660016021463995358397647,0,0,0,0,136008866328797013724770744720365597386442571229108098088496,89408219548852083871843897345095138052614489831075106908453482432,570001187904083526703192267458842116343208221475276329238901428468);
        DynamicKinkModelTester.deposit(1024774440291773);
        DynamicKinkModelTester.borrow(1);
        DynamicKinkModelTester.updateConfig(604195087162326595210432947875422810824884538566718407253604495691485619,8484769277806826242232368349919,12634232008238443438296134508590022060864899230652642014583426732200793,2475394998621960880607585398831142893834784618467735742193915166404463,-115329885579202311745877899892130,215962527331263864,23519965843117509725666,3069888314710420257145356620908696,41371534269749126430231898059,1,438270872303312782183600788587256925901423762092121860883067128411738659,42429507723632025608510948281239903863831085756666553850049432513466);
        DynamicKinkModelTester.borrow(1);
        DynamicKinkModelTester.assert_rcur_slope_below_ucrit();
    }
}
