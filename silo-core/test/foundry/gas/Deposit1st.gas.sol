// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract Deposit1stGasTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();
    }

    // FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_gas_firstDeposit
    //  194207 - when __accrueInterest returns 2 configs
    // -188200  when __accrueInterest returns config and we pul configs in lib
    function test_gas_firstDeposit() public {
        _action(
            BORROWER,
            address(silo0),
            abi.encodeCall(ISilo.deposit, (ASSETS, BORROWER, ISilo.CollateralType.Collateral)),
            "Deposit1st ever",
            167935,
            1000
        );
    }
}
