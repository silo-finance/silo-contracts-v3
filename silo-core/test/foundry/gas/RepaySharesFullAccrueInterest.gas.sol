// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract RepaySharesFullAccrueInterestGasTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        vm.prank(DEPOSITOR);
        silo1.deposit(ASSETS * 5, DEPOSITOR);

        vm.startPrank(BORROWER);
        silo0.deposit(ASSETS * 10, BORROWER);
        silo1.borrow(ASSETS, BORROWER, BORROWER);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
    }

    /*
    forge test -vv --ffi --mt test_gas_repayFullWithInterest
    */
    function test_gas_repayFullWithInterest() public {
        // mint for interest
        token1.mint(BORROWER, ASSETS / 10);

        _action(
            BORROWER,
            address(silo1),
            abi.encodeWithSignature("repay(uint256,address)", ASSETS, BORROWER),
            "RepaySharesFullAccrueInterest full (shares) with accrue interest",
            132882,
            1000
        );
    }
}
