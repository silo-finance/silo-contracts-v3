// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {OpenLeveragePositionReentrancyTest} from "./OpenLeveragePositionReentrancyTest.sol";

contract CloseLeveragePositionReentrancyTest is OpenLeveragePositionReentrancyTest {
    function callMethod() external virtual override {
        _openLeverage();

        address user = wallet.addr;

        (ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs, IGeneralSwapModule.SwapArgs memory swapArgs)
        = _closeLeverageArgs();

        uint256 flashAmount = TestStateLib.silo0().maxRepay(user);

        uint256 amountIn = flashAmount * 111 / 100;
        swap.setSwap(TestStateLib.token1(), amountIn, TestStateLib.token0(), amountIn * 99 / 100);

        // Get user's leverage contract and approve it for collateral share token
        LeverageRouter router = _getLeverageRouter();
        address userLeverageContract = router.predictUserLeverageContract(user);

        address silo1 = address(TestStateLib.silo1());

        vm.prank(user);
        IERC20(silo1).approve(userLeverageContract, type(uint256).max);

        TestStateLib.enableLeverageReentrancy();

        vm.prank(user);
        router.closeLeveragePosition(abi.encode(swapArgs), closeArgs);

        TestStateLib.disableLeverageReentrancy();
    }

    function verifyReentrancy() external virtual override {
        emit log_string("[CloseLeveragePositionReentrancyTest] before closeLeveragePosition");
        LeverageRouter router = _getLeverageRouter();

        bytes memory swapArgs = "";

        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs = ILeverageUsingSiloFlashloan.CloseLeverageArgs({
            flashloanTarget: address(TestStateLib.silo0()),
            siloWithCollateral: TestStateLib.silo1(),
            collateralType: ISilo.CollateralType.Collateral
        });

        address user = wallet.addr;
        vm.prank(user);
        vm.expectRevert(TransientReentrancy.ReentrancyGuardReentrantCall.selector);
        router.closeLeveragePosition(swapArgs, closeArgs);
    }

    function methodDescription() external pure virtual override returns (string memory description) {
        description = "closeLeveragePosition(bytes,(address,address,uint8))";
    }

    function _closeLeverageArgs()
        internal
        view
        returns (
            ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        )
    {
        closeArgs = ILeverageUsingSiloFlashloan.CloseLeverageArgs({
            flashloanTarget: address(TestStateLib.silo0()),
            siloWithCollateral: TestStateLib.silo1(),
            collateralType: ISilo.CollateralType.Collateral
        });

        swapArgs = IGeneralSwapModule.SwapArgs({
            sellToken: TestStateLib.token1(),
            buyToken: TestStateLib.token0(),
            allowanceTarget: address(swap),
            exchangeProxy: address(swap),
            swapCallData: "mocked swap data"
        });
    }
}
