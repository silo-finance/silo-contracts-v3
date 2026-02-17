// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract TransferCollateralTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        _deposit(ASSETS * 2, BORROWER);
        _depositForBorrow(ASSETS, DEPOSITOR);
        _borrow(ASSETS, BORROWER);
    }

    /*
    forge test -vv --ffi --mt test_gas_transferCollateral
    */
    function test_gas_transferCollateral() public {
        (, address collateralShareToken,) = ISiloConfig(silo0.config()).getShareTokens(address(silo0));

        _action(
            BORROWER,
            address(collateralShareToken),
            abi.encodeCall(IERC20.transfer, (BORROWER, 1)),
            "TransferCollateral (when debt)",
            111816
        );
    }
}
