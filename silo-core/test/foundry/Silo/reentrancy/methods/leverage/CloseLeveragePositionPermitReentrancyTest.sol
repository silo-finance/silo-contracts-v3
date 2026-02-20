// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {TestStateLib} from "../../TestState.sol";
import {CloseLeveragePositionReentrancyTest} from "./CloseLeveragePositionReentrancyTest.sol";

contract CloseLeveragePositionPermitReentrancyTest is CloseLeveragePositionReentrancyTest {
    function callMethod() external override {
        _openLeverage();

        (ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs, IGeneralSwapModule.SwapArgs memory swapArgs)
        = _closeLeverageArgs();

        uint256 flashAmount = TestStateLib.silo0().maxRepay(wallet.addr);

        uint256 amountIn = flashAmount * 111 / 100;
        swap.setSwap(TestStateLib.token1(), amountIn, TestStateLib.token0(), amountIn * 99 / 100);

        LeverageRouter router = _getLeverageRouter();

        TestStateLib.enableLeverageReentrancy();

        ILeverageUsingSiloFlashloan.Permit memory permit = _generatePermit(address(TestStateLib.silo1()));

        vm.prank(wallet.addr);
        router.closeLeveragePositionPermit(abi.encode(swapArgs), closeArgs, permit);

        TestStateLib.disableLeverageReentrancy();
    }

    function verifyReentrancy() external override {
        LeverageRouter router = _getLeverageRouter();

        (ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs, IGeneralSwapModule.SwapArgs memory swapArgs)
        = _closeLeverageArgs();

        ILeverageUsingSiloFlashloan.Permit memory permit = _generatePermit(address(TestStateLib.silo0()));

        address user = wallet.addr;
        vm.prank(user);
        vm.expectRevert(TransientReentrancy.ReentrancyGuardReentrantCall.selector);
        router.closeLeveragePositionPermit(abi.encode(swapArgs), closeArgs, permit);
    }

    function methodDescription() external pure override returns (string memory description) {
        // solhint-disable-next-line max-line-length
        description =
            "closeLeveragePositionPermit(bytes,(address,address,uint8),(uint256,uint256,uint8,bytes32,bytes32))";
    }
}
