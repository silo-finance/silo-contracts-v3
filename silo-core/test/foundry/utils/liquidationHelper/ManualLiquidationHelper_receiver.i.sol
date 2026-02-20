// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;



import {ManualLiquidationHelperTest} from "./ManualLiquidationHelper.i.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc ManualLiquidationHelperReceiverTest
*/
contract ManualLiquidationHelperReceiverTest is ManualLiquidationHelperTest {
    function _executeLiquidation() internal override {
        LIQUIDATION_HELPER.executeLiquidation(silo1, BORROWER, 2 ** 128, false, _tokenReceiver());
    }

    function _tokenReceiver() internal view override returns (address payable) {
        return payable(address(this));
    }
}
