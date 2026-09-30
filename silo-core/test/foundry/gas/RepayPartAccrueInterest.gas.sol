// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract RepayPartAccrueInterestGasTest is Gas, Test {
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

    // forge test -vv --ffi --mt test_gas_repayPartWithInterest
    function test_gas_repayPartWithInterest() public {
        _action(
            BORROWER,
            address(silo1),
            abi.encodeWithSignature("repay(uint256,address)", ASSETS / 2, BORROWER),
            "RepayPartAccrueInterest partial with accrue interest",
            140182,
            1000
        );
    }
}
