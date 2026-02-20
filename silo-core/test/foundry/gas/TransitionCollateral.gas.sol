// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract TransitionCollateralTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        _deposit(ASSETS * 2, BORROWER);
        _depositForBorrow(ASSETS, DEPOSITOR);
        _borrow(ASSETS, BORROWER);

        vm.warp(block.timestamp + 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_gas_transitionCollateral
    */
    function test_gas_transitionCollateral() public {
        _action(
            BORROWER,
            address(silo0),
            abi.encodeCall(ISilo.transitionCollateral, (ASSETS, BORROWER, ISilo.CollateralType.Collateral)),
            "transitionCollateral (when debt)",
            292350 // 74K for interest
        );
    }
}
