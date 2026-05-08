// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract WithdrawPartAccrueInterestGasTest is Gas, Test {
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

    // forge test -vv --ffi --mt test_gas_withdrawPartWithInterest
    function test_gas_withdrawPartWithInterest() public {
        _action(
            DEPOSITOR,
            address(silo1),
            abi.encodeCall(ISilo.withdraw, (ASSETS / 10, DEPOSITOR, DEPOSITOR, ISilo.CollateralType.Collateral)),
            "Withdraw partial with accrue interest",
            205504,
            1000
        );
    }
}
