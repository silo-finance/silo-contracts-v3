// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
     FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc WithdrawWhenDebtTest
*/
contract WithdrawWhenDebtTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        // we need to have something to borrow
        _depositForBorrow(0.5e18, address(1));

        _deposit(2e18, address(this), ISilo.CollateralType.Collateral);
        _deposit(1e18, address(this), ISilo.CollateralType.Protected);

        _borrow(0.1e18, address(this));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_withdraw_whenDebt_fuzz
    */
    function test_withdraw_whenDebt_fuzz(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 1e18); // we have to be able to create insolvency in 1sec
        vm.assume(_depositAmount < 2 ** 96);

        address depositor = makeAddr("depositor");
        address borrower = address(this);

        _deposit(_depositAmount, borrower);
        _deposit(_depositAmount, borrower, ISilo.CollateralType.Protected);

        _depositForBorrow(_depositAmount * 5, depositor);
        _borrow(silo1.maxBorrow(borrower), borrower);

        _withdraw(silo0.maxWithdraw(borrower), borrower);

        vm.warp(block.timestamp + 1);

        assertFalse(silo0.isSolvent(borrower), "must be insolvent");

        assertEq(silo0.maxWithdraw(borrower), 0, "should not be able to withdraw more collateral");

        assertEq(
            silo0.maxWithdraw(borrower, ISilo.CollateralType.Protected),
            0,
            "should not be able to withdraw more protected"
        );

        vm.prank(borrower);
        vm.expectRevert(ISilo.NotSolvent.selector);
        silo0.withdraw(1, borrower, borrower);

        vm.prank(borrower);
        vm.expectRevert(ISilo.NotSolvent.selector);
        silo0.withdraw(1, borrower, borrower, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_withdraw_all_possible_Collateral
    */
    function test_withdraw_all_possible_Collateral() public {    
        address borrower = address(this);

        ISilo collateralSilo = silo0;

        (address protectedShareToken, address collateralShareToken,) =
            siloConfig.getShareTokens(address(collateralSilo));
        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));

        // collateral

        uint256 maxWithdraw = collateralSilo.maxWithdraw(address(this)) + 1; // +1 for underestimation
        assertEq(maxWithdraw, 2e18 - 1, "maxWithdraw, because we have protected (-1 for underestimation)");

        uint256 previewWithdraw = collateralSilo.previewWithdraw(maxWithdraw);
        uint256 gotShares =
            collateralSilo.withdraw(maxWithdraw, borrower, borrower, ISilo.CollateralType.Collateral);

        assertEq(collateralSilo.maxWithdraw(address(this)), 0, "no collateral left");

        // you can withdraw more because interest are smaller
        uint256 expectedProtectedWithdraw = 882352941176470588;
        uint256 expectedCollateralLeft = 1e18 - expectedProtectedWithdraw;
        assertLe(0.1e18 * 1e18 / expectedCollateralLeft, 0.85e18, "LTV holds");

        assertTrue(collateralSilo.isSolvent(address(this)), "must stay solvent");

        assertEq(
            collateralSilo.maxWithdraw(address(this), ISilo.CollateralType.Protected),
            expectedProtectedWithdraw - 1,
            "protected maxWithdraw"
        );
        assertEq(previewWithdraw, gotShares, "previewWithdraw");

        assertEq(IShareToken(debtShareToken).balanceOf(address(this)), 0.1e18, "debtShareToken");
        assertEq(
            IShareToken(protectedShareToken).balanceOf(address(this)),
            1e18 * SiloMathLib._DECIMALS_OFFSET_POW,
            "protectedShareToken stays the same"
        );
        assertLe(
            IShareToken(collateralShareToken).balanceOf(address(this)),
            2 * SiloMathLib._DECIMALS_OFFSET_POW,
            "collateral burned"
        );

        assertLe(
            collateralSilo.getCollateralAssets(),
            2,
            "#1 CollateralAssets should be withdrawn (if we withdraw based on max assets, we can underestimate by 2)"
        );

        // protected

        maxWithdraw = collateralSilo.maxWithdraw(address(this), ISilo.CollateralType.Protected);
        assertEq(maxWithdraw, expectedProtectedWithdraw - 1, "maxWithdraw, protected");

        previewWithdraw = collateralSilo.previewWithdraw(maxWithdraw, ISilo.CollateralType.Protected);
        gotShares = collateralSilo.withdraw(maxWithdraw, borrower, borrower, ISilo.CollateralType.Protected);

        assertEq(
            collateralSilo.maxWithdraw(address(this), ISilo.CollateralType.Protected),
            0,
            "no protected withdrawn left"
        );

        assertEq(previewWithdraw, gotShares, "protected previewWithdraw");

        assertEq(IShareToken(debtShareToken).balanceOf(address(this)), 0.1e18, "debtShareToken");

        assertEq(
            IShareToken(protectedShareToken).balanceOf(address(this)),
            (expectedCollateralLeft + 1) * SiloMathLib._DECIMALS_OFFSET_POW,
            "protectedShareToken"
        );

        assertLe(
            collateralSilo.getCollateralAssets(),
            2,
            "#2 CollateralAssets should be withdrawn (if we withdraw based on max assets, we can underestimate by 2)"
        );

        assertTrue(collateralSilo.isSolvent(address(this)), "must be solvent 1");
        assertTrue(silo1.isSolvent(address(this)), "must be solvent 2");
    }
}
