// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {SiloHarness} from "silo-core/test/foundry/_mocks/SiloHarness.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc MaxBorrowAndFractions

    Testing scenarios and result with and without fix in the SiloLendingLib.sol.maxBorrowValueToAssetsAndShares fn
    // assets--;
    In this test, we expect to have no reverts

    results for maxBorrow => borrow

    borrow 50
        scenario 1 - revert AboveMaxLtv (fix solves the issue)
        scenario 2 - revert AboveMaxLtv (fix solves the issue)
        scenario 3 - succeeds (no changes)

    borrow max / 2
        scenario 1 - revert AboveMaxLtv (fix solves the issue)
        scenario 2 - revert AboveMaxLt (fix solves the issue)
        scenario 3 - succeeds (no changes)

    borrow 0
        scenario 1 - revert AboveMaxLtv (fix solves the issue)
        scenario 2 - revert AboveMaxLtv (fix solves the issue)
        scenario 3 - succeeds (no changes)

    scenario 1 (interest 1 revenue 0)
        SiloHarness(payable(address(silo1))).increaseTotalDebtAssets(1);

    scenario 2 (interest 1 revenue 1)
        SiloHarness(payable(address(silo1))).increaseTotalDebtAssets(1);
        SiloHarness(payable(address(silo1))).increaseTotalCollateralAssets(1);

    scenario 3 (interest 0 revenue 1)
        SiloHarness(payable(address(silo1))).decreaseTotalCollateralAssets(1);

    Note: scenario 3 always succeeds, because of the liquidityWithInterest -= 1 in the calculateMaxBorrow fn
*/
contract MaxBorrowAndFractions is SiloLittleHelper, Test {
    uint256 public snapshot;

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
    function test_maxBorrow_WithFractions_any_scenario_fuzz(
        uint256 _firstBorrowAmount,
        uint256 _depositAmount,
        bool _borrowShares,
        uint8 _scenario
    ) public {
        // (uint256 _firstBorrowAmount,
        //     uint256 _depositAmount,
        //     bool _borrowShares,
        //     uint8 _scenario) = (760, 16880, false, 3);

        vm.assume(_depositAmount != 0 && _depositAmount < type(uint128).max);
        _doDeposit(_depositAmount);

        uint256 maxBorrow = silo1.maxBorrow(address(this));

        // We need to create a debt before testing, because of that `_firstBorrowAmount` should be < `maxBorrow`.
        // Otherwise, the test will fail because we will not be able to borrow a second time.
        uint256 randomChunk = _firstBorrowAmount % 900;
        vm.assume(_firstBorrowAmount != 0 && _firstBorrowAmount <= maxBorrow * randomChunk / 1000);
        vm.assume(_scenario == 1 || _scenario == 2 || _scenario == 3);

        if (_scenario == 1) {
            _executeBorrowScenario1(_firstBorrowAmount, _borrowShares);
        } else if (_scenario == 2) {
            _executeBorrowScenario2(_firstBorrowAmount, _borrowShares);
        } else if (_scenario == 3) {
            _executeBorrowScenario3(_firstBorrowAmount, _borrowShares);
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrow_Borrow_WithFractions_scenario1

    scenario 1 - increase total debt assets
    */
    function test_maxBorrow_Borrow_WithFractions_scenario1() public {
        bool borrowShares = false;

        _executeBorrowScenario1(50, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario1(silo1.maxBorrow(address(this)) / 2, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario1(0, borrowShares);
        vm.revertToState(snapshot);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrow_BorrowShares_WithFractions_scenario1

    scenario 1 - increase total debt assets
    */
    function test_maxBorrow_BorrowShares_WithFractions_scenario1() public {
        bool borrowShares = true;

        _executeBorrowScenario1(50, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario1(silo1.maxBorrow(address(this)) / 2, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario1(0, borrowShares);
        vm.revertToState(snapshot);
    }

    function _executeBorrowScenario1(uint256 _firstBorrowAmount, bool _borrowShares) internal {
        address borrower = address(this);
        _borrowAndUpdateSiloCode(_firstBorrowAmount);

        if (_borrowShares) {
            uint256 maxBorrowShares = silo1.maxBorrowShares(borrower);

            if (silo1.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo1))).increaseTotalDebtAssets(1);
            }

            vm.assume(maxBorrowShares != 0);
            silo1.borrowShares(maxBorrowShares, borrower, borrower);
        } else {
            uint256 maxBorrow = silo1.maxBorrow(borrower);

            if (silo1.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo1))).increaseTotalDebtAssets(1);
            }

            vm.assume(maxBorrow != 0);
            silo1.borrow(maxBorrow, borrower, borrower);
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrow_borrow_WithFractions_scenario2

    scenario 2 - increase total collateral and debt assets
    */
    function test_maxBorrow_borrow_WithFractions_scenario2() public {
        bool borrowShares = false;

        _executeBorrowScenario2(50, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario2(silo1.maxBorrow(address(this)) / 2, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario2(0, borrowShares);
        vm.revertToState(snapshot);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrow_borrowShares_WithFractions_scenario2

    scenario 2 - increase total collateral and debt assets
    */
    function test_maxBorrow_borrowShares_WithFractions_scenario2() public {
        bool borrowShares = true;

        _executeBorrowScenario2(50, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario2(silo1.maxBorrow(address(this)) / 2, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario2(0, borrowShares);
        vm.revertToState(snapshot);
    }

    function _executeBorrowScenario2(uint256 _firstBorrowAmount, bool _borrowShares) internal {
        address borrower = address(this);
        _borrowAndUpdateSiloCode(_firstBorrowAmount);

        if (_borrowShares) {
            uint256 maxBorrowShares = silo1.maxBorrowShares(borrower);
            _changeTotalsScenario2();
            vm.assume(maxBorrowShares != 0);
            silo1.borrowShares(maxBorrowShares, borrower, borrower);
        } else {
            uint256 maxBorrow = silo1.maxBorrow(borrower);
            _changeTotalsScenario2();
            vm.assume(maxBorrow != 0);
            silo1.borrow(maxBorrow, borrower, borrower);
        }
    }

    function _changeTotalsScenario2() internal {
        if (silo1.getDebtAssets() != 0) return; // no debt - no interest

        SiloHarness(payable(address(silo1))).increaseTotalDebtAssets(1);
        SiloHarness(payable(address(silo1))).increaseTotalCollateralAssets(1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowWithFractions

    scenario 3 - decrease total collateral assets
    */
    function test_maxBorrowWithFractions_scenario3() public {
        bool borrowShares = false;

        _executeBorrowScenario3(50, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario3(silo1.maxBorrow(address(this)) / 2, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario3(0, borrowShares);
        vm.revertToState(snapshot);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxBorrowWithFractions_borrowShares_scenario3

    scenario 3 - decrease total collateral assets
    */
    function test_maxBorrowWithFractions_borrowShares_scenario3() public {
        bool borrowShares = true;

        _executeBorrowScenario3(50, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario3(silo1.maxBorrow(address(this)) / 2, borrowShares);
        vm.revertToState(snapshot);

        _executeBorrowScenario3(0, borrowShares);
        vm.revertToState(snapshot);
    }

    function _executeBorrowScenario3(uint256 _firstBorrowAmount, bool _borrowShares) internal {
        address borrower = address(this);
        _borrowAndUpdateSiloCode(_firstBorrowAmount);

        if (_borrowShares) {
            uint256 maxBorrowShares = silo1.maxBorrowShares(borrower);

            if (silo1.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo1))).decreaseTotalCollateralAssets(1);
            }

            vm.assume(maxBorrowShares != 0);
            silo1.borrowShares(maxBorrowShares, borrower, borrower);
        } else {
            uint256 maxBorrow = silo1.maxBorrow(borrower);

            if (silo1.getDebtAssets() != 0) {
                // no debt - no interest
                SiloHarness(payable(address(silo1))).decreaseTotalCollateralAssets(1);
            }

            vm.assume(maxBorrow != 0);
            silo1.borrow(maxBorrow, borrower, borrower);
        }
    }

    function _doDeposit(uint256 _amount) internal {
        silo0.mint(_amount, address(this));
        silo1.deposit(_amount, address(1));
    }

    function _borrowAndUpdateSiloCode(uint256 _amount) internal returns (uint256 maxBorrow) {
        address borrower = address(this);

        if (_amount != 0) {
            silo1.borrow(_amount, borrower, borrower);
        }

        address silo1Harness = address(new SiloHarness(ISiloFactory(address(this))));

        vm.etch(address(silo1), address(silo1Harness).code);

        ISilo.Fractions memory fractions = silo1.getFractionsStorage();
        assertEq(fractions.interest, 0, "interest should be 0");
        assertEq(fractions.revenue, 0, "revenue should be 0");

        emit log_named_uint("silo0.balanceOf", silo0.balanceOf(borrower));
        emit log_named_uint("silo0.previewRedeem", silo0.previewRedeem(silo0.balanceOf(borrower)));
        emit log_named_uint("silo1.maxRepay", silo1.maxRepay(borrower));

        maxBorrow = silo1.maxBorrow(borrower);
        assertNotEq(maxBorrow, 0, "maxBorrow should not be 0");
    }
}
