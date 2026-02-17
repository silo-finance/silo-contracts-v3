// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {RescueModule} from "silo-core/contracts/leverage/modules/RescueModule.sol";

contract CloseLeveragePositionPermitDirectReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert with OnlyRouter"));
        _ensureItWillRevertWithOnlyRouter();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertWithOnlyRouter();
    }

    function methodDescription() external pure returns (string memory description) {
        description =
            "closeLeveragePositionPermit(address,bytes,(address,address,uint8),(uint256,uint256,uint8,bytes32,bytes32))";
    }

    function _ensureItWillRevertWithOnlyRouter() internal {
        LeverageUsingSiloFlashloanWithGeneralSwap leverage = _getLeverage();

        bytes memory swapArgs = "";

        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs = ILeverageUsingSiloFlashloan.CloseLeverageArgs({
            siloWithCollateral: TestStateLib.silo1(),
            flashloanTarget: address(TestStateLib.silo0()),
            collateralType: ISilo.CollateralType.Collateral
        });

        ILeverageUsingSiloFlashloan.Permit memory withdrawAllowance = ILeverageUsingSiloFlashloan.Permit({
            value: 100e18,
            deadline: block.timestamp + 1 hours,
            v: 27,
            r: bytes32(0),
            s: bytes32(0)
        });

        // This should revert with OnlyRouter error
        vm.expectRevert(RescueModule.OnlyRouter.selector);
        leverage.closeLeveragePositionPermit(address(this), swapArgs, closeArgs, withdrawAllowance);
    }

    function _getLeverage() internal view returns (LeverageUsingSiloFlashloanWithGeneralSwap) {
        ILeverageRouter leverageRouter = ILeverageRouter(TestStateLib.leverageRouter());
        return LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION());
    }
}
