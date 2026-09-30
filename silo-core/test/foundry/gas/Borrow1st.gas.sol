// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract Borrow1stGasTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        vm.prank(BORROWER);
        silo0.deposit(ASSETS * 2, BORROWER);

        vm.prank(DEPOSITOR);
        silo1.deposit(ASSETS, DEPOSITOR);
    }

    function test_gas_firstBorrow() public {
        _action(
            BORROWER,
            address(silo1),
            abi.encodeCall(ISilo.borrow, (ASSETS, BORROWER, BORROWER)),
            "Borrow1st (no interest)",
            230787,
            1000
        );
    }
}
