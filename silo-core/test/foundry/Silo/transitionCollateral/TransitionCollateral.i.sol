// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mc TransitionCollateralTest
*/
contract TransitionCollateralTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_zeros
    */
    function test_transitionCollateral_zeros() public {
        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.transitionCollateral(0, address(0), ISilo.CollateralType(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_noCollateral_ownerZero
    */
    function test_transitionCollateral_noCollateral_ownerZero() public {
        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.transitionCollateral(1, address(0), ISilo.CollateralType(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_noCollateral_shareZero
    */
    function test_transitionCollateral_noCollateral_shareZero() public {
        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.transitionCollateral(0, address(1), ISilo.CollateralType(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_wrongCollateral
    */
    function test_transitionCollateral_wrongCollateral() public {
        _deposit(10, address(this));

        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.transitionCollateral(1, address(1), ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_toProtected
    */
    function test_transitionCollateral_toProtected() public {
        address owner = address(this);

        _deposit(10, owner);

        silo0.transitionCollateral(1 * SiloMathLib._DECIMALS_OFFSET_POW, owner, ISilo.CollateralType.Collateral);

        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));

        assertEq(
            IShareToken(protectedShareToken).balanceOf(owner),
            1 * SiloMathLib._DECIMALS_OFFSET_POW,
            "protectedShareToken balance"
        );
        assertEq(
            IShareToken(collateralShareToken).balanceOf(owner),
            9 * SiloMathLib._DECIMALS_OFFSET_POW,
            "collateralShareToken balance"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_toCollateral
    */
    function test_transitionCollateral_toCollateral() public {
        address owner = address(this);

        _deposit(10, owner, ISilo.CollateralType.Protected);

        silo0.transitionCollateral(2 * SiloMathLib._DECIMALS_OFFSET_POW, owner, ISilo.CollateralType.Protected);

        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));

        assertEq(
            IShareToken(protectedShareToken).balanceOf(owner),
            8 * SiloMathLib._DECIMALS_OFFSET_POW,
            "protectedShareToken balance"
        );
        assertEq(
            IShareToken(collateralShareToken).balanceOf(owner),
            2 * SiloMathLib._DECIMALS_OFFSET_POW,
            "collateralShareToken balance"
        );

        _withdraw(2, owner);
        _withdraw(8, owner, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_otherOwner
    */
    function test_transitionCollateral_otherOwner() public {
        address otherOwner = makeAddr("otherOwner");

        _deposit(10, otherOwner, ISilo.CollateralType.Protected);
        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));

        vm.prank(otherOwner);
        IShareToken(protectedShareToken).approve(address(this), 2 * SiloMathLib._DECIMALS_OFFSET_POW);

        silo0.transitionCollateral(2 * SiloMathLib._DECIMALS_OFFSET_POW, otherOwner, ISilo.CollateralType.Protected);

        assertEq(
            IShareToken(protectedShareToken).balanceOf(otherOwner),
            8 * SiloMathLib._DECIMALS_OFFSET_POW,
            "protectedShareToken balance"
        );
        assertEq(
            IShareToken(collateralShareToken).balanceOf(otherOwner),
            2 * SiloMathLib._DECIMALS_OFFSET_POW,
            "collateralShareToken"
        );

        _withdraw(2, otherOwner);
        _withdraw(8, otherOwner, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_withDebt
    */
    function test_transitionCollateral_withDebt() public {
        address owner = address(this);

        _deposit(10, owner, ISilo.CollateralType.Protected);
        _depositForBorrow(7, makeAddr("depositor"));
        _borrow(7, owner);

        silo0.transitionCollateral(5 * SiloMathLib._DECIMALS_OFFSET_POW, owner, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_withInterest_solvent
    */
    function test_transitionCollateral_withInterest_solvent() public {
        address owner = address(this);

        _deposit(1e18, owner, ISilo.CollateralType.Protected);
        _depositForBorrow(0.7e18, makeAddr("depositor"));
        _borrow(0.7e18, owner);

        vm.warp(block.timestamp + 3 days);

        assertTrue(silo0.isSolvent(owner), "this test is for solvent user");

        silo0.transitionCollateral(0.5e18, owner, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_withInterest_inSolvent
    */
    function test_transitionCollateral_withInterest_inSolvent() public {
        address owner = address(this);

        _deposit(1e18, owner, ISilo.CollateralType.Protected);
        _depositForBorrow(0.7e18, makeAddr("depositor"));
        _borrow(0.7e18, owner);

        vm.warp(block.timestamp + 100 days);

        vm.expectRevert(ISilo.NotSolvent.selector);
        silo0.transitionCollateral(0.5e18, owner, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral_deposit_inSolvent
    */
    function test_transitionCollateral_deposit_inSolvent() public {
        address owner = address(this);

        _deposit(1e18, owner, ISilo.CollateralType.Protected);
        _depositForBorrow(0.7e18, owner); // this is not collateral!

        _depositForBorrow(0.7e18, makeAddr("depositor"));
        _borrow(silo1.maxBorrow(owner), owner);

        vm.warp(block.timestamp + 200 days);
        assertFalse(silo0.isSolvent(owner), "expect insolvent for this test");

        uint256 gasStart = gasleft();
        silo1.transitionCollateral({_shares: 1e3, _owner: owner, _transitionFrom: ISilo.CollateralType.Collateral});
        emit log_named_uint("gas for transitionCollateral", gasStart - gasleft()); // 180582 => 167639
    }
}
