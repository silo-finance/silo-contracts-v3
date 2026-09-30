// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract OnFlashLoanReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        _expectRevert();
    }

    function verifyReentrancy() external {
        _expectRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "onFlashLoan(address,address,uint256,uint256,bytes)";
    }

    function _expectRevert() internal {
        LeverageUsingSiloFlashloanWithGeneralSwap leverage = _getLeverage();

        vm.prank(makeAddr("Some address"));

        vm.expectRevert(ILeverageUsingSiloFlashloan.InvalidFlashloanLender.selector);

        leverage.onFlashLoan(address(this), address(0), 100e18, 1e18, "");
    }

    function _getLeverage() internal view returns (LeverageUsingSiloFlashloanWithGeneralSwap) {
        ILeverageRouter leverageRouter = ILeverageRouter(TestStateLib.leverageRouter());
        return LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION());
    }
}
