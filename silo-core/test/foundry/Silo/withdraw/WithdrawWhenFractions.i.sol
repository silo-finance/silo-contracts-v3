// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc WithdrawWhenFractionsTest
*/
contract WithdrawWhenFractionsTest is SiloLittleHelper, Test {
    function setUp() public {
        _setUpLocalFixture();

        token0.setOnDemand(true);
        token1.setOnDemand(true);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_withdraw_when_fractions
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_withdraw_when_fractions_fuzz(uint256 _borrowAmount, bool _maxRedeem) public {
        vm.assume(_borrowAmount < uint256(632707) * 80 / 100);
        vm.assume(_borrowAmount > 0);

        _withdraw_when_fractions(_borrowAmount, _maxRedeem);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_withdraw_when_fractions
    this test will fail for maxWithdraw when we not count for interest fractions
    */
    function test_withdraw_when_fractions() public {
        _withdraw_when_fractions(44723, false);
    }

    function _withdraw_when_fractions(uint256 _borrowAmount, bool _maxRedeem) public {
        vm.warp(337812);
        vm.assume(_borrowAmount / 2 != 0);

        address borrower = address(this);

        silo0.mint(632707868, borrower);
        silo1.mint(632707868, borrower);
        _borrow(_borrowAmount / 2, borrower);

        vm.warp(block.timestamp + 195346);
        silo1.accrueInterest();
        ISilo.Fractions memory fractions = silo1.getFractionsStorage();
        vm.assume(fractions.interest != 0);

        vm.warp(block.timestamp + 130008);

        if (_maxRedeem) {
            vm.assume(silo1.maxRedeem(borrower) != 0);
            silo1.redeem(silo1.maxRedeem(borrower), borrower, borrower);
        } else {
            vm.assume(silo1.maxWithdraw(borrower) != 0);
            silo1.withdraw(silo1.maxWithdraw(borrower), borrower, borrower);
        }
    }
}
