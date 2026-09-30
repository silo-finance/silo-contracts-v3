// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CantinaTicket} from "./CantinaTicket.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc CantinaTicket239
*/
contract CantinaTicket239 is CantinaTicket {
    function test_repay_early_accrue_interest_rate() public {
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");
        uint128 assets = 1e18;

        // 1. Bob supplies tokens
        _depositForBorrow(assets, bob);
        _deposit(assets, bob);

        vm.warp(block.timestamp + 1 days);

        // 2: Alice supplies and borrows assets
        _createDebt(assets, alice);

        // 3: Bob accruing interest
        vm.warp(block.timestamp + 10 days);
        // In PoC they check collateral
        uint256 amountBeforeRepay = silo1.getCollateralAssets(); // get collat amount with interest

        // 4: Alice repays all debt
        _repayShares(silo1.maxRepay(alice), silo1.maxRepayShares(alice), alice);
        assertEq(silo1.maxRepay(alice), 0, "no more debt");
        assertEq(SILO_LENS.getLtv(silo1, alice), 0, "LTV 0");

        uint256 amountAfterRepay = silo1.getCollateralAssets(); // get collat amount with interest
        assertEq(amountBeforeRepay, amountAfterRepay, "incorrect interest calculation");

        uint256 debtAfterRepay = silo1.getDebtAssets();

        // but interest rate keeps accruing for Bob
        vm.warp(block.timestamp + 100 days);

        assertEq(amountAfterRepay, silo1.getCollateralAssets(), "no interest on collateral");
        assertEq(debtAfterRepay, silo1.getDebtAssets(), "no interest on debt");
    }
}
