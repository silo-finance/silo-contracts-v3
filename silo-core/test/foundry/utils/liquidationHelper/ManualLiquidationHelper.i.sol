// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;


import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {ManualLiquidationHelperCommon} from "./ManualLiquidationHelperCommon.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc ManualLiquidationHelperTest
*/
contract ManualLiquidationHelperTest is ManualLiquidationHelperCommon {
    uint256 constant LIQUIDATION_UNDERESTIMATION = 2;

    function setUp() public {
        vm.label(BORROWER, "BORROWER");
        siloConfig = _setUpLocalFixture();

        _depositForBorrow(DEBT + COLLATERAL, makeAddr("depositor"));
        _deposit(COLLATERAL, BORROWER);
        _borrow(DEBT, BORROWER);

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(address(silo0));

        assertEq(collateralConfig.liquidationFee, 0.05e18, "liquidationFee");

        _debtAsset = address(token1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_executeLiquidation -vvv
    */
    function test_executeLiquidation(uint64 _addTimestamp) public {
        vm.assume(block.timestamp + _addTimestamp < 2 ** 64 - 1);
        vm.warp(block.timestamp + _addTimestamp);

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);

        emit log_named_decimal_uint("collateralToLiquidate", collateralToLiquidate, 18);
        emit log_named_decimal_uint("          debtToRepay", debtToRepay, 18);
        vm.assume(debtToRepay != 0);

        token1.mint(address(this), debtToRepay);
        token1.approve(address(LIQUIDATION_HELPER), debtToRepay);

        assertEq(token0.balanceOf(_tokenReceiver()), 0, "no collateral before liquidation");

        _executeLiquidation();

        uint256 withdrawCollateral = token0.balanceOf(_tokenReceiver());

        assertEq(
            collateralToLiquidate,
            withdrawCollateral - LIQUIDATION_UNDERESTIMATION,
            "collateralToLiquidate == withdrawCollateral"
        );

        emit log_named_decimal_uint("token0.balanceOf(_tokenReceiver())", token0.balanceOf(_tokenReceiver()), 18);
        emit log_named_decimal_uint("token1.balanceOf(_tokenReceiver())", token1.balanceOf(_tokenReceiver()), 18);

        _assertAddressHasNoSTokens(silo0, _tokenReceiver());
        _assertAddressHasNoSTokens(silo1, _tokenReceiver());

        assertTrue(silo0.isSolvent(BORROWER), "borrower must be solvent after manual liquidation");
    }
}
