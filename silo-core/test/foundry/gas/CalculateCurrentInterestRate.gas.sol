// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract CalculateCurrentInterestRateGasTest is Gas, Test {
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

    function test_gas_calculateCurrentInterestRate() public {
        ISiloConfig.ConfigData memory config = silo1.config().getConfig(address(silo1));

        IInterestRateModelV2.Config memory c =
            IInterestRateModelV2(config.interestRateModel).getConfig(address(silo1));
        ISilo.UtilizationData memory data = ISilo(silo1).utilizationData();

        _action(
            DEPOSITOR,
            config.interestRateModel,
            abi.encodeCall(
                IInterestRateModelV2.calculateCurrentInterestRate,
                (
                    c,
                    data.collateralAssets,
                    data.debtAssets,
                    data.interestRateTimestamp,
                    data.interestRateTimestamp + 30 days
                )
            ),
            "CalculateCurrentInterestRate",
            13028
        );
    }
}
