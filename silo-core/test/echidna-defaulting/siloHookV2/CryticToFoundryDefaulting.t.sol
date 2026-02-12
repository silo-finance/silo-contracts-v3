// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/* solhint-disable */

import {console2} from "forge-std/console2.sol";

// Libraries
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";

// Contracts
import {SetupDefaulting} from "./SetupDefaulting.t.sol";
import {BaseHandlerDefaulting} from "./base/BaseHandlerDefaulting.t.sol";
import {DefaultBeforeAfterHooks} from "silo-core/test/invariants/hooks/DefaultBeforeAfterHooks.t.sol";
import {Invariants} from "silo-core/test/invariants/Invariants.t.sol";
import {DefaultingHandler} from "./handlers/user/DefaultingHandler.t.sol";

// solhint-disable function-max-lines, func-name-mixedcase

/*
 * Test suite that converts from  "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract CryticToFoundryDefaulting is Invariants, DefaultingHandler, SetupDefaulting {
    CryticToFoundryDefaulting public DefaultingTester = this;
    CryticToFoundryDefaulting public Target = this;

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
    FOUNDRY_PROFILE=echidna_defaulting forge test -vv --ffi --mt test_EchidnaDefaulting_empty
    */
    function test_EchidnaDefaulting_empty() public {}

    /*
    FOUNDRY_PROFILE=echidna_defaulting forge test -vv --ffi --mt test_EchidnaDefaulting_test2
    */
    function test_EchidnaDefaulting_test2() public {
        _setUpActor(USER1);
        Target.deposit(1017867300, 255, 154, 152);
        _setUpActor(USER1);
        Target.mint(7111713077508456469, 56, 247, 255);
        _delay(0x5f36, 0xdb1e);
        _setUpActor(USER1);
        Target.assertBORROWING_HSPOST_F(255, 255);
        _delay(0x84344, 0x9abc);
        _setUpActor(USER1);
        Target.assert_defaulting_price1();
        _delay(0x13417, 0x2bb2);
        _setUpActor(USER1);
        Target.assert_defaulting_totalAssetsIsNotLessThanLiquidity();
        _delay(0x71e3a, 0xeaa1);
        _setUpActor(USER1);
        Target.deposit(103942843829821916262830942653128025804425797611087637966294849975061662195270, 35, 30, 255);
        _delay(0x2bd1c, 0x6392);
        _setUpActor(USER2);
        Target.assert_defaulting_totalAssetsIsNotLessThanLiquidity();
        _delay(0x74057, 0x3d63);
        _setUpActor(USER1);
        Target.liquidationCall(2794043644144, false, RandomGenerator(255, 146, 0));
        _setUpActor(USER1);
        Target.assert_LENDING_INVARIANT_B(216, 122);
        _delay(0x7f467, 0xabd9);
        _setUpActor(USER1);
        Target.setOraclePrice(1194144534193741270213735117138418, 12);
        _delay(0x2c83b, 0x18);
        _setUpActor(USER1);
        Target.receiveAllowance(4939, 3, 26, 13);
        _delay(0x4647f, 0x1097);
        _setUpActor(USER1);
        Target.accrueInterestForSilo(0);
        _delay(0x35361, 0x47fd);
        _setUpActor(USER1);
        Target.redeem(15241046242, 201, 121, 51);
        _delay(0x866f3, 0x3df5);
        _setUpActor(USER1);
        Target.accrueInterest(179);
        _delay(0x38252, 0x85ab);
        _setUpActor(USER1);
        Target.repay(174590089, 37, 76);
        _delay(0x2fd85, 0xe98);
        _setUpActor(USER1);
        Target.approve(12, 107, 14);
        _delay(0x7c279, 0x3168);
        _setUpActor(USER1);
        Target.transfer(41423330505857396159155861457666608144691816007497169336636200277649435230440, 8, 98);
        _delay(0x76e49, 0x590a);
        _setUpActor(USER1);
        Target.accrueInterestForSilo(41);
        _delay(0x4821b, 0xb9a);
        _setUpActor(USER1);
        Target.borrow(89198472592584626845696818725833454757642320225748433841547145926155650798269, 3, 136);
        _delay(0x932c, 0x5300);
        _setUpActor(USER1);
        Target.assert_claimRewardsCanBeAlwaysDone(2);
        _delay(0x2f994, 0xc63);
        _setUpActor(USER1);
        Target.accrueInterest(17);
    }

    /*
    FOUNDRY_PROFILE=echidna_defaulting forge test -vv --ffi --mt test_EchidnaDefaulting_maxWitgdrawBug
    this test fails with `ERC20InsufficientBalance` error on withdraw(maxWithdraw)
    */
    function test_EchidnaDefaulting_maxWitgdrawBug() public {
        _delay(0x2d67e, 0x94d4);
        _setUpActor(USER1);
        Target.flashLoan(33997933614, 59720891045440504036478328204482, 255, 255);
        _delay(0x1116d, 0x696a);
        _setUpActor(USER2);
        Target.flashLoan(141, 3490240572148739115283646203988286917862725275911766428893275924779700305261, 223, 255);
        _delay(0x8f9df, 0x13e);
        _setUpActor(USER3);
        Target.setDaoFee(951, 4369999);
        _delay(0x177, 0xe0d0);
        _setUpActor(USER3);
        Target.accrueInterestForSilo(255);
        _delay(0x64ad6, 0x185a);
        _setUpActor(USER2);
        Target.repayShares(41554817557094186064533894015130926811343312575249145325483587144519081482914, 58, 255);
        _delay(0x63f8d, 0x7e5b);
        _setUpActor(USER3);
        Target.mint(365045, 254, 53, 255);
        _delay(0x75, 0xdd0);
        _setUpActor(USER1);
        Target.repayShares(311072328, 255, 255);
        _delay(0x42655, 0x5b6b);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(
            RandomGenerator(255, 74, 255)
        );
        _delay(0x8af1a, 0x320);
        _setUpActor(USER1);
        Target.increaseReceiveAllowance(346, 0, 5);
        _delay(0x142ef, 0x1740);
        _setUpActor(USER2);
        Target.liquidationCall(
            67728972471006198986298227812770245613331157852673164503068484645059995572823,
            false,
            RandomGenerator(160, 157, 255)
        );
        _delay(0x6a2ce, 0x8ffb);
        _setUpActor(USER1);
        Target.repay(4369999, 189, 91);
        _delay(0x4a9a4, 0x2f15);
        _setUpActor(USER2);
        Target.transfer(1524785993, 255, 11);
        _delay(0x1051, 0x7210);
        _setUpActor(USER3);
        Target.repayShares(95892808007310130461726393477978320535191969378337819859309698314584970665759, 191, 160);
        _delay(0x62e05, 0xff);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(
            RandomGenerator(114, 255, 197)
        );
        _delay(0x103ef, 0x95ce);
        _setUpActor(USER2);
        Target.borrowShares(4370001, 13, 255);
        _delay(0x65373, 0x5c65);
        _setUpActor(USER3);
        Target.approve(1524785993, 255, 252);
        _delay(0x65410, 0xdefe);
        _setUpActor(USER1);
        Target.repayShares(494, 179, 255);
        _delay(0x65373, 0x7630);
        _setUpActor(USER2);
        Target.liquidationCall(4370000, false, RandomGenerator(255, 255, 32));
        _delay(0x307c6, 0x20ff);
        _setUpActor(USER1);
        Target.transitionCollateral(
            115792089237316195423570985008687907853269984665640564039457584007913129639931,
            RandomGenerator(255, 190, 255)
        );
        _delay(0x475d0, 0xa663);
        _setUpActor(USER1);
        Target.liquidationCallByDefaulting(
            RandomGenerator(76, 83, 255)
        );
        _delay(0x6fa94, 0xe59f);
        _setUpActor(USER1);
        Target.setReceiveApproval(4370000, 14, 57);
        _delay(0x6a9f7, 0x5c65);
        _setUpActor(USER3);
        Target.setReceiveApproval(384, 91, 255);
        _delay(0x6fde0, 0x2c55);
        _setUpActor(USER2);
        Target.approve(27148545692374155322291941503308178963530265868509743399535280528644029865215, 255, 235);
        _delay(0x62e05, 0x2ea6);
        _setUpActor(USER2);
        Target.deposit(4369999, 255, 153, 136);
        _delay(0x66815, 0x20ff);
        _setUpActor(USER1);
        Target.borrowShares(27911167801869684515744473000929147500345948956948960096806928214355651970206, 123, 222);
        _delay(0x1b73c, 0x7f);
        _setUpActor(USER1);
        Target.redeem(69804035102822899763494712667121677177454622072505461205402417414177107505946, 60, 255, 255);
        _delay(0x1b73c, 0x7fff);
        _setUpActor(USER1);
        Target.decreaseReceiveAllowance(1524785993, 71, 255);
        _delay(0x4daf5, 0xd38b);
        _setUpActor(USER2);
        Target.MIN_PRICE();
        _delay(0x576ad, 0xd1ae);
        _setUpActor(USER1);
        Target.redeem(115792089237316195423570985008687907853269984665640564039457584007913129639933, 14, 136, 28);
        _delay(0x4daf5, 0xcfae);
        _setUpActor(USER2);
        Target.decreaseReceiveAllowance(4369999, 255, 254);
        _delay(0x11d50, 0x2e81);
        _setUpActor(USER1);
        Target.approve(84650142505917377559005533300925546105801758978925122315120759991916446545247, 135, 162);
        _delay(0x3e1ce, 0xd13a);
        _setUpActor(USER3);
        Target.withdraw(1524785992, 255, 97, 106);
        _delay(0x7d1b7, 0x87a0);
        _setUpActor(USER1);
        Target.decreaseReceiveAllowance(4370000, 255, 255);
        _delay(0x475d0, 0xe142);
        _setUpActor(USER2);
        Target.setOraclePrice(58160580489700127668469870347581330043227444339977370134949532548299805865648, 255);
        _delay(0x6c82f, 0xa4a9);
        _setUpActor(USER3);
        Target.deposit(79035511232824199074153207416910770763102106856489416349797366457525449527355, 186, 255, 255);
        _delay(0x189e3, 0x753b);
        _setUpActor(USER1);
        Target.accrueInterestForBothSilos();
        _delay(0x65410, 0x5d4d);
        _setUpActor(USER1);
        Target.withdraw(530780513563034613288841675059373940962231014741194921737403, 239, 255, 255);
        _delay(0x77bd0, 0x94d4);
        _setUpActor(USER2);
        Target.accrueInterestForBothSilos();
        _delay(0x4daf5, 0x20);
        _setUpActor(USER3);
        Target.liquidationCallByDefaulting(
            RandomGenerator(255, 255, 255)
        );
        _delay(0x3340a, 0x7f);
        _setUpActor(USER3);
        Target.accrueInterestForBothSilos();
        _delay(0x8dde9, 0x116e);
        _setUpActor(USER1);
        Target.receiveAllowance(
            29882650456281084738190043830201979887566836706330072603560922513535419521132, 228, 255, 204
        );
        _delay(0x65ba5, 0xa475);
        _setUpActor(USER1);
        Target.accrueInterestForBothSilos();
        _delay(0x1cae0, 0xea4d);
        _setUpActor(USER2);
        Target.repayShares(122794517411283, 254, 169);
        _delay(0x6d464, 0x87a0);
        _setUpActor(USER1);
        Target.liquidationCall(
            110342258604813883136076491391080051692563040975227526460641868343995084633246,
            false,
            RandomGenerator(12, 255, 255)
        );
        _delay(0x74d9f, 0xb2fb);
        _setUpActor(USER2);
        Target.mint(28649857434211785716785075571150725017899301465750003284002157044320271768204, 105, 38, 254);
        _delay(0x7fff, 0x1740);
        _setUpActor(USER1);
        Target.repayShares(71708458556377148034738526920072027328540892681006375790390644571284132856343, 193, 166);
        _delay(0x3256a, 0xd38b);
        _setUpActor(USER1);
        Target.MAX_PRICE();
        _delay(0x4daf5, 0x95ce);
        _setUpActor(USER3);
        Target.assert_BORROWING_HSPOST_D(252, 255);
        _delay(0xb3d0, 0xd13a);
        _setUpActor(USER3);
        Target.setOraclePrice(95081893068143359407883104546296025957664557752771364132166348654363223148495, 65);
        _delay(0x65373, 0x9de);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(
            RandomGenerator(87, 179, 255)
        );
        _delay(0x4eac7, 0xe4d);
        _setUpActor(USER2);
        Target.accrueInterestForBothSilos();
        _delay(0x7d1b7, 0xcf13);
        _setUpActor(USER3);
        Target.MIN_PRICE();
        _delay(0x7f7c2, 0xff);
        _setUpActor(USER2);
        Target.repay(96630375201925410040082539982734416186641267585699916877556906461429592050050, 213, 255);
        _delay(0x103ef, 0x107f);
        _setUpActor(USER3);
        Target.liquidationCallByDefaulting(
            RandomGenerator(255, 240, 255)
        );
        _delay(0x46b47, 0xd619);
        _setUpActor(USER1);
        Target.repay(60330835776423846165004771220335477365446027906003784432952490792006788440388, 34, 241);
        _delay(0x8f9df, 0x13be);
        _setUpActor(USER2);
        Target.assert_BORROWING_HSPOST_D(220, 255);
        _delay(0x70f0, 0x5c65);
        _setUpActor(USER2);
        Target.deposit(1524785992, 45, 192, 255);
        _delay(0x5dfb0, 0x2f15);
        _setUpActor(USER2);
        Target.assertBORROWING_HSPOST_F(255, 137);
        _delay(0x1051, 0x7d93);
        _setUpActor(USER3);
        Target.increaseReceiveAllowance(
            115792089237316195423570985008687907853269984665640564039457584007913129639934, 255, 255
        );
        _delay(0x142ef, 0xd0cb);
        _setUpActor(USER3);
        Target.setReceiveApproval(
            115792089237316195423570985008687907853269984665640564039457584007913129639935, 172, 255
        );
        _delay(0x76ea6, 0x9cf);
        _setUpActor(USER2);
        Target.setOraclePrice(115792089237316195423570985008687907853269984665640564039457584007913129639934, 161);
        _delay(0x5f467, 0x89b0);
        _setUpActor(USER3);
        Target.borrow(1524785993, 187, 122);
        _delay(0x62123, 0x1c9b);
        _setUpActor(USER1);
        Target.assert_LENDING_INVARIANT_B(255, 36);
        _delay(0xb056, 0x753b);
        _setUpActor(USER2);
        Target.redeem(106781997506895828704624214719419180173846986714878297331960770258476324553957, 0, 255, 1);
        _delay(0x8345, 0x4ddd);
        _setUpActor(USER1);
        Target.assert_BORROWING_HSPOST_D(252, 255);
        _delay(0x3e1ce, 0xcfae);
        _setUpActor(USER1);
        Target.mint(8833740862598790822298872322557078511982463963928588332032819512705882315246, 247, 118, 255);
        _delay(0x6b721, 0xe59f);
        _setUpActor(USER3);
        Target.assertBORROWING_HSPOST_F(255, 255);
        _delay(0x6123, 0x320);
        _setUpActor(USER1);
        Target.setReceiveApproval(
            42433951474074729361621982518820040054100203943647270879125385874743773798748, 130, 24
        );
        _delay(0x582b0, 0x20ff);
        _setUpActor(USER3);
        Target.approve(82109049031960918442738176079186229578228170818505220915176958281990161257318, 255, 255);
        _delay(0x1f113, 0x2f7b);
        _setUpActor(USER2);
        Target.increaseReceiveAllowance(68, 25, 255);
        _delay(0xffff, 0xd8f2);
        _setUpActor(USER2);
        Target.repayShares(0, 181, 255);
        _delay(0x24b01, 0x30cd);
        _setUpActor(USER2);
        Target.assert_SILO_HSPOST_D(255);
        _delay(0x214c8, 0xcfae);
        _setUpActor(USER3);
        Target.accrueInterestForBothSilos();
        _delay(0x329b9, 0x320);
        _setUpActor(USER1);
        Target.borrow(4369999, 15, 42);
        _delay(0x1b73c, 0x440);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(RandomGenerator(61, 14, 255));
        _delay(0x5408b, 0x26ee);
        _setUpActor(USER2);
        Target.receiveAllowance(1524785992, 224, 255, 22);
        _delay(0x212f1, 0x1414);
        _setUpActor(USER1);
        Target.increaseReceiveAllowance(
            61337461536744140313660380324818011942477261825176834788369124471526107825961, 255, 255
        );
        _delay(0x6b504, 0x552);
        _setUpActor(USER2);
        Target.receiveAllowance(1524785991, 151, 255, 239);
        _delay(0x4a0f1, 0xb556);
        _setUpActor(USER1);
        Target.MAX_PRICE();
        _delay(0x4eb46, 0x8980);
        _setUpActor(USER1);
        Target.liquidationCall(1524785991, false, RandomGenerator(3, 255, 255));
        _delay(0x42655, 0xd619);
        _setUpActor(USER3);
        Target.repayShares(7820336472698723259836837139630046202385603710161591492277320897963474743784, 68, 255);
        _delay(0x48651, 0x463);
        _setUpActor(USER2);
        Target.assertBORROWING_HSPOST_F(140, 0);
        _delay(0x52e28, 0xd619);
        _setUpActor(USER3);
        Target.setReceiveApproval(416, 128, 33);
        _delay(0x1ae49, 0x5c65);
        _setUpActor(USER3);
        Target.assert_LENDING_INVARIANT_B(255, 156);
        _delay(0x75d98, 0x7f);
        _setUpActor(USER1);
        Target.approve(62210178003067872032363862593697997573465648818003862600306593549124497195450, 80, 135);
        _delay(0x46b47, 0x8ffb);
        _setUpActor(USER3);
        Target.accrueInterestForSilo(14);
        _delay(0x81f7, 0x1a41);
        _setUpActor(USER2);
        Target.assert_BORROWING_HSPOST_D(49, 255);
        _delay(0x1cae0, 0x1320);
        _setUpActor(USER2);
        Target.liquidationCall(4370001, false, RandomGenerator(149, 21, 118));
        _delay(0x7b6a, 0x9d0);
        _setUpActor(USER2);
        Target.redeem(4370000, 255, 26, 215);
        _delay(0x7d1b7, 0x755a);
        _setUpActor(USER3);
        Target.borrow(65585194715669205132739287491084670852465903559164611781706710043332307970603, 255, 81);
        _delay(0x6a2ce, 0xcf13);
        _setUpActor(USER1);
        Target.mint(1524785991, 137, 255, 228);
        _delay(0x576ad, 0xdefe);
        _setUpActor(USER2);
        Target.receiveAllowance(262117389025040960656941050858116432210996162521186349, 255, 255, 24);
        _delay(0x1cae0, 0x7630);
        _setUpActor(USER3);
        Target.decreaseReceiveAllowance(
            115792089237316195423570985008687907853269984665640564039457584007913129639933, 0, 17
        );
        _delay(0x4a0f1, 0x26c0);
        _setUpActor(USER1);
        Target.setReceiveApproval(
            38619747731699152230644537703097785233519251829562314810378839206026474715870, 134, 255
        );
        _delay(0x2f08c, 0x753b);
        _setUpActor(USER1);
        Target.mint(0, 255, 202, 255);
        _delay(0x2fa33, 0x6b0c);
        _setUpActor(USER1);
        Target.transferFrom(4370001, 172, 255, 3);
        _delay(0xff, 0x279e);
        _setUpActor(USER2);
        Target.borrow(115792089237316195423570985008687907853269984665640564039457584007913129639932, 255, 41);
        _delay(0x214c8, 0xd8f2);
        _setUpActor(USER3);
        Target.liquidationCallByDefaulting(
            RandomGenerator(43, 255, 0)
        );
        _delay(0x28928, 0xc107);
        _setUpActor(USER1);
        Target.assert_BORROWING_HSPOST_D(255, 185);
        _delay(0x307c6, 0x5b6b);
        _setUpActor(USER2);
        Target.repay(4370001, 227, 173);
        _delay(0x77bce, 0x5aeb);
        _setUpActor(USER3);
        Target.assertBORROWING_HSPOST_F(255, 169);
        _delay(0x1f113, 0x3c08);
        _setUpActor(USER1);
        Target.transfer(4370001, 85, 255);
        _delay(0x51251, 0x2c55);
        _setUpActor(USER1);
        Target.accrueInterestForSilo(181);
        _delay(0x142ef, 0xa475);
        _setUpActor(USER1);
        Target.borrowShares(0, 255, 255);
        _delay(0x41a2, 0xa4f5);
        _setUpActor(USER2);
        Target.transitionCollateral(884, RandomGenerator(110, 255, 46));
        _delay(0x5bd20, 0x2e32);
        _setUpActor(USER1);
        Target.increaseReceiveAllowance(1524785993, 62, 255);
        _delay(0x62e05, 0x5c65);
        _setUpActor(USER3);
        Target.transfer(22944587289367568746250287521237882356293243266981018442209355429155904556762, 60, 213);
        _delay(0xb056, 0xc854);
        _setUpActor(USER2);
        Target.assert_SILO_HSPOST_D(255);
        _delay(0x7d1b7, 0x26c0);
        _setUpActor(USER3);
        Target.accrueInterest(56);
        _delay(0x7cf4e, 0x277e);
        _setUpActor(USER2);
        Target.mint(1524785992, 108, 255, 255);
        _delay(0x4a55, 0xb2fb);
        _setUpActor(USER3);
        Target.mint(1524785992, 47, 255, 189);
        _delay(0x3340a, 0x597d);
        _setUpActor(USER3);
        Target.accrueInterestForSilo(230);
        _delay(0x62123, 0xd1ae);
        _setUpActor(USER3);
        Target.assertBORROWING_HSPOST_F(255, 255);
        _delay(0x46b47, 0x1320);
        _setUpActor(USER2);
        Target.MAX_PRICE();
        _delay(0x3340a, 0xd619);
        _setUpActor(USER3);
        Target.liquidationCallByDefaulting(RandomGenerator(125, 252, 255));
        _delay(0x7f467, 0x3b9a);
        _setUpActor(USER3);
        Target.repay(1524785992, 117, 255);
        _delay(0x81f7, 0x753b);
        _setUpActor(USER1);
        Target.liquidationCallByDefaulting(RandomGenerator(56, 40, 126));
        _delay(0x6d464, 0xea4f);
        _setUpActor(USER1);
        Target.assert_SILO_HSPOST_D(115);
        _delay(0x4a55, 0x30cd);
        _setUpActor(USER1);
        Target.repay(736, 251, 191);
        _delay(0x1c18d, 0xe5d2);
        _setUpActor(USER1);
        Target.repay(4369999, 255, 255);
        _delay(0x80772, 0x94d4);
        _setUpActor(USER1);
        Target.liquidationCall(
            106723709733403423642092629950696877456986098004742726315960636427595273783252,
            true,
            RandomGenerator(156, 255, 195)
        );
        _delay(0x142f0, 0x5caa);
        _setUpActor(USER1);
        Target.liquidationCallByDefaulting(
            RandomGenerator(157, 255, 138)
        );
        _delay(0x142ef, 0x7630);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(
            RandomGenerator(255, 255, 83)
        );
        _delay(0x29247, 0x8ffb);
        _setUpActor(USER2);
        Target.setReceiveApproval(
            69826747835200643904221383016200815059410222286299230890513773756116249034947, 255, 119
        );
        _delay(0x804a4, 0xff);
        _setUpActor(USER3);
        Target.borrowShares(1524785991, 29, 255);
        _delay(0x6b504, 0x440);
        _setUpActor(USER2);
        Target.borrowShares(4369999, 198, 255);
        _delay(0x4694f, 0x30cd);
        _setUpActor(USER1);
        Target.MAX_PRICE();
        _delay(0x6123, 0x755a);
        _setUpActor(USER3);
        Target.mint(1524785991, 187, 225, 24);
        _delay(0x4a9a4, 0x6c9c);
        _setUpActor(USER3);
        Target.receiveAllowance(
            88968095358741298776878563895436183321799220856386626409567278712462649867910, 255, 212, 255
        );
        _delay(0x65410, 0xea96);
        _setUpActor(USER1);
        Target.accrueInterestForSilo(247);
        _delay(0x307c6, 0x5ef7);
        _setUpActor(USER2);
        Target.accrueInterestForBothSilos();
        _delay(0x42655, 0x58ab);
        _setUpActor(USER1);
        Target.mint(1524785991, 24, 21, 194);
        _delay(0x8f9df, 0x5daa);
        _setUpActor(USER1);
        Target.mint(1524785991, 154, 16, 68);
        _delay(0x80772, 0x755a);
        _setUpActor(USER2);
        Target.transitionCollateral(
            21409319520113706690308350931635367003876811136146692412440777169173698490652,
            RandomGenerator(255, 255, 176)
        );
        _delay(0x2621e, 0xb31c);
        _setUpActor(USER1);
        Target.setReceiveApproval(
            77337307715719400453942886950771053198709764232338099106449501237073269072113, 255, 255
        );
        _delay(0x1051, 0xe8a0);
        _setUpActor(USER3);
        Target.MAX_PRICE();
        _delay(0x74813, 0xdfb9);
        _setUpActor(USER1);
        Target.repay(4369999, 255, 255);
        _delay(0x51251, 0x26ee);
        _setUpActor(USER1);
        Target.setReceiveApproval(
            105048994818534055222674767794995888465534041843482300461275270909882071990677, 255, 222
        );
        _delay(0x142ee, 0x3c08);
        _setUpActor(USER2);
        Target.transferFrom(
            10193277817637005360558734678678705754054357859575678243450813619098131614745, 52, 244, 255
        );
        _delay(0x52be8, 0x3032);
        _setUpActor(USER2);
        Target.setOraclePrice(1524785992, 70);
        _delay(0x11d50, 0xea4d);
        _setUpActor(USER1);
        Target.repayShares(1524785993, 254, 255);
        _delay(0x6b721, 0x1320);
        _setUpActor(USER3);
        Target.deposit(37294160861839470945715928029075211652654478420596236659019067592348287092651, 163, 255, 255);
        _delay(0x329b9, 0x116e);
        _setUpActor(USER2);
        Target.receiveAllowance(485, 255, 14, 255);
        _delay(0x94ab, 0x5b6b);
        _setUpActor(USER3);
        Target.MIN_PRICE();
        _delay(0x2a045, 0x5ef7);
        _setUpActor(USER2);
        Target.transferFrom(
            115792089237316195423570985008687907853269984665640564039457584007913129639935, 255, 255, 255
        );
        _delay(0x64ad5, 0xe8a0);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(
            RandomGenerator(62, 255, 253)
        );
        _delay(0x37272, 0x7660);
        _setUpActor(USER1);
        Target.assert_BORROWING_HSPOST_D(255, 163);
        _delay(0x41a2, 0xa663);
        _setUpActor(USER2);
        Target.approve(1524785991, 128, 76);
        _delay(0x4694f, 0xc85a);
        _setUpActor(USER3);
        Target.accrueInterest(69);
        _delay(0x77bd0, 0x5ef7);
        _setUpActor(USER2);
        Target.approve(115792089237316195423570985008687907853269984665640564039457584007913129639934, 255, 122);
        _delay(0x4694f, 0x95ce);
        _setUpActor(USER3);
        Target.liquidationCallByDefaulting(
            RandomGenerator(231, 99, 179)
        );
        _delay(0x52be8, 0x13bd);
        _setUpActor(USER2);
        Target.accrueInterestForSilo(247);
        _delay(0x214ca, 0x30cd);
        _setUpActor(USER2);
        Target.transitionCollateral(
            2905524548308743158965956862307356415408958468470663656910024000301346978550, RandomGenerator(255, 0, 99)
        );
        _delay(0x307c6, 0x2e32);
        _setUpActor(USER3);
        Target.transitionCollateral(
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            RandomGenerator(255, 115, 206)
        );
        _delay(0x5f467, 0x5aeb);
        _setUpActor(USER1);
        Target.borrowShares(1524785992, 255, 128);
        _delay(0x307c6, 0x3c09);
        _setUpActor(USER2);
        Target.MAX_PRICE();
        _delay(0x2a045, 0xd38b);
        _setUpActor(USER3);
        Target.transfer(4912473, 156, 117);
        _delay(0xff, 0x9cf);
        _setUpActor(USER3);
        Target.MAX_PRICE();
        _delay(0x2a045, 0x9cf);
        _setUpActor(USER2);
        Target.MAX_PRICE();
        _delay(0x576ad, 0xd1ae);
        _setUpActor(USER1);
        Target.transferFrom(
            90318476213917949728386927160082259735316458568522904138088398235816897711407, 255, 255, 125
        );
        _delay(0x76ea6, 0x87a0);
        _setUpActor(USER1);
        Target.increaseReceiveAllowance(4369999, 99, 255);
        _delay(0x85b27, 0x94d4);
        _setUpActor(USER3);
        Target.borrow(113798795689622209078082902835866625882421236862259084249738652943360546215072, 44, 255);
        _delay(0x11d50, 0x2ea6);
        _setUpActor(USER3);
        Target.transferFrom(
            110083703931358221363076659603373759752367532300390439908929586863011616324167, 17, 252, 255
        );
        _delay(0x3256a, 0x8980);
        _setUpActor(USER1);
        Target.assert_BORROWING_HSPOST_D(166, 90);
        _delay(0x81f7, 0x755a);
        _setUpActor(USER1);
        Target.transitionCollateral(
            9185236013203816443548148432183170538667391471045253198729267642083338298609,
            RandomGenerator(255, 255, 229)
        );
        _delay(0x6a2ce, 0xd13a);
        _setUpActor(USER3);
        Target.assert_LENDING_INVARIANT_B(20, 192);
        _delay(0x42655, 0x231);
        _setUpActor(USER1);
        Target.liquidationCallByDefaulting(
            RandomGenerator(35, 255, 67)
        );
        _delay(0x5617a, 0x1c9b);
        _setUpActor(USER1);
        Target.accrueInterest(255);
        _delay(0x3340a, 0x89b0);
        _setUpActor(USER1);
        Target.liquidationCall(
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            false,
            RandomGenerator(255, 255, 169)
        );
        _delay(0x712e4, 0x9d0);
        _setUpActor(USER2);
        Target.liquidationCallByDefaulting(
            RandomGenerator(255, 40, 64)
        );
        _delay(0x43af0, 0xa663);
        _setUpActor(USER2);
        Target.transitionCollateral(
            5118569183195425567126660190276278917075707430839223737981446780898544030189,
            RandomGenerator(111, 255, 42)
        );
        _delay(0x75d98, 0x769a);
        _setUpActor(USER2);
        Target.borrowShares(4370001, 150, 255);
        _delay(0x80772, 0xa4f5);
        _setUpActor(USER1);
        Target.receiveAllowance(
            15034577099901710996919593284599078084840332859386219662641994623747670967148, 112, 227, 11
        );
        _delay(0x4694f, 0xdcf6);
        _setUpActor(USER2);
        Target.MIN_PRICE();
        _delay(0x7cf4e, 0x9de);
        _setUpActor(USER3);
        Target.liquidationCallByDefaulting(
            RandomGenerator(8, 255, 18)
        );
        _delay(0xb056, 0x13bd);
        _setUpActor(USER1);
        Target.receiveAllowance(
            45850619002861701817056430916337683895700250925567096412401997802148956417440, 125, 255, 53
        );
        _delay(0x7f467, 0x20ff);
        _setUpActor(USER2);
        Target.assert_SILO_HSPOST_D(255);
        _delay(0x5eb90, 0x13be);
        _setUpActor(USER2);
        Target.transferFrom(
            90508370297569908360089741359687802433805485817034804351043343463550528335829, 191, 46, 70
        );
        _delay(0x94ab, 0x3032);
        _setUpActor(USER1);
        Target.assertBORROWING_HSPOST_F(255, 255);
        _delay(0x103ef, 0xeb6b);
        _setUpActor(USER2);
        Target.MAX_PRICE();
        _delay(0x63720, 0x619b);
        _setUpActor(USER2);
        Target.liquidationCall(
            52143517035722306241620094494644035298324747384704421554497690072878146922462,
            true,
            RandomGenerator(230, 255, 255)
        );
        _delay(0x214ca, 0x3c07);
        _setUpActor(USER3);
        Target.decreaseReceiveAllowance(4370001, 162, 255);
        _delay(0x214c8, 0xa475);
        _setUpActor(USER1);
        Target.assert_BORROWING_HSPOST_D(193, 112);
        _delay(0x28928, 0xeb6b);
        _setUpActor(USER3);
        Target.accrueInterestForBothSilos();
        _delay(0x212f1, 0x116e);
        _setUpActor(USER1);
        Target.borrow(95712136588299355648674910592899302043562829991942056757117289105891532633412, 115, 255);
        _delay(0x37272, 0x2233);
        _setUpActor(USER3);
        Target.withdraw(42958727274043012777606106640142975125725909267727616435433289209571573629132, 10, 255, 164);
        _delay(0x48a23, 0x1c9b);
        _setUpActor(USER3);
        Target.accrueInterest(255);
        _delay(0x74d9f, 0xe4d);
        _setUpActor(USER1);
        Target.liquidationCall(
            12534804810458885577279800138304601393139274961850757441096174455635091621820,
            true,
            RandomGenerator(255, 194, 255)
        );
        _delay(0x46b47, 0xd0cb);
        _setUpActor(USER1);
        Target.borrowShares(4370000, 255, 170);
        _delay(0x64ad5, 0xe8a0);
        _setUpActor(USER1);
        Target.increaseReceiveAllowance(874424080892720, 14, 0);
        _delay(0x668ee, 0x30cd);
        _setUpActor(USER3);
        Target.assert_LENDING_INVARIANT_B(171, 255);
    }

    function _delay(uint256 timeInSeconds, uint256 numBlocks) internal {
        vm.warp(block.timestamp + timeInSeconds);
        vm.roll(block.number + numBlocks);
    }

    function _setUpActor(address actor) internal {
        // actor is set up for each fn based on random params, so we don;t need ot do anything here
        // this is just a placeholder to satisfy the compiler
        // vm.startPrank(actor);
        // Add any additional actor setup here if needed
    }

    function _defaultHooksBefore(address silo) internal override(BaseHandlerDefaulting, DefaultBeforeAfterHooks) {
        BaseHandlerDefaulting._defaultHooksBefore(silo);
    }
}
