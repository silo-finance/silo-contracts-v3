// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {TestStateLib} from "../../TestState.sol";
import {OpenLeveragePositionReentrancyTest} from "./OpenLeveragePositionReentrancyTest.sol";

contract OpenLeveragePositionPermitReentrancyTest is OpenLeveragePositionReentrancyTest {
    function callMethod() external override {
        address user = wallet.addr;
        uint256 depositAmount = 0.1e18;
        uint256 flashloanAmount = depositAmount * 1.08e18 / 1e18;

        _depositLiquidity();
        _mintUserTokensAndApprove(user, depositAmount, flashloanAmount, swap, true);

        // Prepare leverage arguments
        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _prepareLeverageArgs(flashloanAmount, depositAmount);

        // mock the swap: debt token -> collateral token, price is 1:1, lt's mock some fee
        swap.setSwap(TestStateLib.token0(), flashloanAmount, TestStateLib.token1(), flashloanAmount * 99 / 100);

        TestStateLib.enableLeverageReentrancy();

        // Execute leverage position opening
        LeverageRouter router = _getLeverageRouter();
        ILeverageUsingSiloFlashloan.Permit memory permit = _generatePermit(TestStateLib.token0());

        vm.prank(user);
        router.openLeveragePositionPermit({
            _flashArgs: flashArgs,
            _swapArgs: abi.encode(swapArgs),
            _depositArgs: depositArgs,
            _depositAllowance: permit
        });

        TestStateLib.disableLeverageReentrancy();
    }

    function verifyReentrancy() external override {
        address user = wallet.addr;

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _prepareLeverageArgs(0, 0);

        // Execute leverage position opening
        LeverageRouter router = _getLeverageRouter();

        ILeverageUsingSiloFlashloan.Permit memory permit = _generatePermit(TestStateLib.token0());

        vm.prank(user);
        vm.expectRevert(TransientReentrancy.ReentrancyGuardReentrantCall.selector);
        router.openLeveragePositionPermit(flashArgs, abi.encode(swapArgs), depositArgs, permit);
    }

    function methodDescription() external pure override returns (string memory description) {
        description = // solhint-disable-next-line max-line-length
            "openLeveragePositionPermit((address,uint256),bytes,(address,uint256,uint8),(uint256,uint256,uint8,bytes32,bytes32))";
    }
}
