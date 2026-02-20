// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {SiloHarness} from "silo-core/test/foundry/_mocks/SiloHarness.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxWithdrawAndFractionsTest
*/
contract MaxWithdrawAndFractionsTest is SiloLittleHelper, Test {
    uint256 public snapshot;
    address public borrower = address(this);
    address public otherUser = makeAddr("otherUser");

    function setUp() public {
        ISiloConfig siloConfig = _setUpLocalFixture();

        assertTrue(siloConfig.getConfig(address(silo0)).maxLtv != 0, "we need borrow to be allowed");

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        uint256 depositAmount = 1e6;
        _doDeposit(depositAmount);

        snapshot = vm.snapshotState();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrow_WithFractions_any_scenario_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxWithdraw_WithFractions_any_scenario_fuzz(
        uint256 _borrowAmount,
        uint256 _depositAmount,
        bool _redeem,
        uint8 _scenario
    ) public {
        vm.assume(_depositAmount != 0 && _depositAmount < type(uint128).max);
        _doDeposit(_depositAmount);

        uint256 maxBorrow = silo1.maxBorrow(address(this));

        vm.assume(_borrowAmount != 0);
        vm.assume(_borrowAmount <= maxBorrow);
        vm.assume(_scenario == 1 || _scenario == 2 || _scenario == 3);

        if (_scenario == 1) {
            _executeWithdrawScenario1(_borrowAmount, _redeem);
        } else if (_scenario == 2) {
            _executeWithdrawScenario2(_borrowAmount, _redeem);
        } else if (_scenario == 3) {
            _executeWithdrawScenario3(_borrowAmount, _redeem);
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_Withdraw_WithFractions_scenario1

    scenario 1 - increase total debt assets
    */
    function test_maxWithdraw_Withdraw_WithFractions_scenario1() public {
        bool redeem = false;

        _executeWithdrawScenario1(50, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario1(silo0.maxBorrow(borrower) / 2, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario1(0, redeem);
        vm.revertToState(snapshot);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxRedeem_Redeem_WithFractions_scenario1

    scenario 1 - increase total debt assets
    */
    function test_maxRedeem_Redeem_WithFractions_scenario1() public {
        bool redeem = true;

        _executeWithdrawScenario1(50, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario1(silo0.maxBorrow(borrower) / 2, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario1(0, redeem);
        vm.revertToState(snapshot);
    }

    function _executeWithdrawScenario1(uint256 _borrowAmount, bool _redeem) internal {
        _borrowAndUpdateSiloCode(_borrowAmount);

        if (_redeem) {
            uint256 maxRedeem = silo0.maxRedeem(borrower);

            if (silo0.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo0))).increaseTotalDebtAssets(1);
            }

            vm.assume(maxRedeem != 0);
            silo0.redeem(maxRedeem, borrower, borrower);
        } else {
            uint256 maxWithdraw = silo0.maxWithdraw(borrower);

            if (silo0.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo0))).increaseTotalDebtAssets(1);
            }

            vm.assume(maxWithdraw != 0);
            silo0.withdraw(maxWithdraw, borrower, borrower);
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_Withdraw_WithFractions_scenario2

    scenario 2 - increase total collateral and debt assets
    */
    function test_maxWithdraw_Withdraw_WithFractions_scenario2() public {
        bool redeem = false;

        _executeWithdrawScenario2(50, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario2(silo0.maxBorrow(borrower) / 2, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario2(0, redeem);
        vm.revertToState(snapshot);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxRedeem_Redeem_WithFractions_scenario2

    scenario 2 - increase total collateral and debt assets
    */
    function test_maxRedeem_Redeem_WithFractions_scenario2() public {
        bool redeem = true;

        _executeWithdrawScenario2(50, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario2(silo0.maxBorrow(borrower) / 2, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario2(0, redeem);
        vm.revertToState(snapshot);
    }

    function _executeWithdrawScenario2(uint256 _borrowAmount, bool _redeem) internal {
        _borrowAndUpdateSiloCode(_borrowAmount);

        if (_redeem) {
            _changeTotalsScenario2();
            uint256 maxRedeem = silo0.maxRedeem(borrower);
            vm.assume(maxRedeem != 0);
            silo0.redeem(maxRedeem, borrower, borrower);
        } else {
            uint256 maxWithdraw = silo0.maxWithdraw(borrower);
            _changeTotalsScenario2();
            vm.assume(maxWithdraw != 0);
            silo0.withdraw(maxWithdraw, borrower, borrower);
        }
    }

    function _changeTotalsScenario2() internal {
        if (silo0.getDebtAssets() != 0) return; // no debt - no interest

        SiloHarness(payable(address(silo0))).increaseTotalDebtAssets(1);
        SiloHarness(payable(address(silo1))).increaseTotalCollateralAssets(1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdrawWithFractions_scenario3

    scenario 3 - decrease total collateral assets
    */
    function test_maxWithdrawWithFractions_scenario3() public {
        bool redeem = false;

        _executeWithdrawScenario3(50, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario3(silo0.maxBorrow(borrower) / 2, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario3(0, redeem);
        vm.revertToState(snapshot);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxRedeemWithFractions_Redeem_scenario3

    scenario 3 - decrease total collateral assets
    */
    function test_maxRedeemWithFractions_Redeem_scenario3() public {
        bool redeem = true;

        _executeWithdrawScenario3(50, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario3(silo0.maxBorrow(borrower) / 2, redeem);
        vm.revertToState(snapshot);

        _executeWithdrawScenario3(0, redeem);
        vm.revertToState(snapshot);
    }

    function _executeWithdrawScenario3(uint256 _borrowAmount, bool _redeem) internal {
        _borrowAndUpdateSiloCode(_borrowAmount);

        if (_redeem) {
            uint256 maxRedeem = silo0.maxRedeem(borrower);

            if (silo0.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo0))).decreaseTotalCollateralAssets(1);
            }

            vm.assume(maxRedeem != 0);
            silo0.redeem(maxRedeem, borrower, borrower);
        } else {
            uint256 maxWithdraw = silo0.maxWithdraw(borrower);

            if (silo0.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo0))).decreaseTotalCollateralAssets(1);
            }

            vm.assume(maxWithdraw != 0);
            silo0.withdraw(maxWithdraw, borrower, borrower);
        }
    }

    function _doDeposit(uint256 _amount) internal {
        silo0.mint(_amount, borrower);
        silo1.deposit(_amount, otherUser);
    }

    function _borrowAndUpdateSiloCode(uint256 _amount) internal returns (uint256 maxWithdraw) {
        if (_amount != 0) {
            silo1.borrow(_amount, borrower, borrower);

            uint256 otherUserBorrowAmount = _amount / 2;

            if (otherUserBorrowAmount != 0) {
                vm.prank(otherUser);
                silo0.borrow(otherUserBorrowAmount, otherUser, otherUser);
            }
        }

        address siloHarness = address(new SiloHarness(ISiloFactory(address(this))));

        vm.etch(address(silo0), address(siloHarness).code);
        vm.etch(address(silo1), address(siloHarness).code);

        ISilo.Fractions memory fractions = silo0.getFractionsStorage();
        assertEq(fractions.interest, 0);
        assertEq(fractions.revenue, 0);

        maxWithdraw = silo0.maxWithdraw(borrower);
        assertNotEq(maxWithdraw, 0);
    }
}
