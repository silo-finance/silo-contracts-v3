// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract LiquidationAccrueInterestGasTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        vm.prank(DEPOSITOR);
        silo1.deposit(ASSETS, DEPOSITOR);

        vm.startPrank(BORROWER);
        silo0.deposit(ASSETS * 5, BORROWER);
        silo1.borrow(ASSETS, BORROWER, BORROWER);
        vm.stopPrank();

        vm.warp(block.timestamp + 13 days);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_gas_liquidationCallWithInterest
    */
    function test_gas_liquidationCallWithInterest() public {
        vm.prank(DEPOSITOR);
        token1.approve(address(partialLiquidation), type(uint256).max);

        _action(
            DEPOSITOR,
            address(partialLiquidation),
            abi.encodeCall(
                IPartialLiquidation.liquidationCall, (address(token0), address(token1), BORROWER, ASSETS / 2, false)
            ),
            "LiquidationCall with accrue interest",
            465895,
            3000
        );
    }
}
