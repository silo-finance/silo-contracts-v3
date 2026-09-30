// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]' | sort
*/
contract Borrow2ndGasTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        vm.prank(DEPOSITOR);
        silo1.deposit(ASSETS * 5, DEPOSITOR);

        vm.startPrank(BORROWER);
        silo0.deposit(ASSETS * 10, BORROWER);
        silo1.borrow(ASSETS, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function test_gas_secondBorrow() public {
        _action(
            BORROWER,
            address(silo1),
            abi.encodeCall(ISilo.borrow, (ASSETS, BORROWER, BORROWER)),
            "Borrow2nd (no interest)",
            141540,
            1000
        );
    }
}
