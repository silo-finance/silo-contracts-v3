// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";
import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";
import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc LiquidationHelperAccessTest
*/
contract LiquidationHelperAccessTest is Test {
    LiquidationHelper internal liquidationHelper;
    ManualLiquidationHelper internal manualLiquidationHelper;

    address internal attacker = makeAddr("attacker");

    function setUp() public {
        liquidationHelper = new LiquidationHelper({
            _nativeToken: makeAddr("nativeToken"),
            _exchangeProxy: makeAddr("exchangeProxy"),
            _tokensReceiver: payable(makeAddr("tokensReceiver"))
        });

        manualLiquidationHelper = new ManualLiquidationHelper({
            _nativeToken: makeAddr("nativeToken"),
            _tokensReceiver: payable(makeAddr("tokensReceiver"))
        });
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_onFlashLoan_closed_direct
    */
    function test_onFlashLoan_closed_direct() public {
        vm.expectRevert(LiquidationHelper.UnauthorizedFlashLoanCallback.selector);
        // positional: first param is unnamed in LiquidationHelper.onFlashLoan
        liquidationHelper.onFlashLoan(address(0), makeAddr("debt"), 1, 0, bytes(""));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_onFlashLoan_closed_fuzz
    */
    function test_onFlashLoan_closed_fuzz(
        address _caller,
        address _initiator,
        address _debtAsset,
        uint256 _maxDebtToCover,
        uint256 _fee,
        bytes calldata _data
    ) public {
        // `_expectedFlashLoanProvider` defaults to address(0); a prank from 0 would pass the callback check.
        vm.assume(_caller != address(0));

        vm.prank(_caller);
        vm.expectRevert(LiquidationHelper.UnauthorizedFlashLoanCallback.selector);
        liquidationHelper.onFlashLoan(_initiator, _debtAsset, _maxDebtToCover, _fee, _data);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_executeLiquidation_onlyAllowed
    */
    function test_executeLiquidation_onlyAllowed() public {
        ILiquidationHelper.LiquidationData memory liquidation;
        ILiquidationHelper.DexSwapInput[] memory swaps;

        vm.prank(attacker);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        liquidationHelper.executeLiquidation({
            _flashLoanFrom: ISilo(makeAddr("silo")),
            _debtAsset: makeAddr("debt"),
            _maxDebtToCover: 1,
            _liquidation: liquidation,
            _swapsInputs0x: swaps
        });
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_manualExecuteLiquidation_onlyAllowed
    */
    function test_manualExecuteLiquidation_onlyAllowed() public {
        vm.prank(attacker);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        manualLiquidationHelper.executeLiquidation({
            _siloWithDebt: ISilo(makeAddr("silo")),
            _borrower: makeAddr("borrower")
        });
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_manualExecuteLiquidation_fullArgs_onlyAllowed
    */
    function test_manualExecuteLiquidation_fullArgs_onlyAllowed() public {
        vm.prank(attacker);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        manualLiquidationHelper.executeLiquidation({
            _siloWithDebt: ISilo(makeAddr("silo")),
            _borrower: makeAddr("borrower"),
            _maxDebtToCover: 1,
            _receiveSToken: false
        });
    }
}
