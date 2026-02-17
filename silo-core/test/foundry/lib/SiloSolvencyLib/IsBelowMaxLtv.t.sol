// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloSolvencyLib} from "silo-core/contracts/lib/SiloSolvencyLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

contract IsBelowMaxLtv {
    function isBelowMaxLtv(
        ISiloConfig.ConfigData memory _collateralConfig,
        ISiloConfig.ConfigData memory _debtConfig,
        address _borrower,
        ISilo.AccrueInterestInMemory _accrueInMemory
    ) external view returns (bool) {
        return SiloSolvencyLib.isBelowMaxLtv(_collateralConfig, _debtConfig, _borrower, _accrueInMemory);
    }
}
/*
forge test --ffi -vv --mc IsBelowMaxLtvTest
*/

contract IsBelowMaxLtvTest is Test, SiloLittleHelper {
    ISiloConfig siloConfig;

    IsBelowMaxLtv immutable impl;

    constructor() {
        impl = new IsBelowMaxLtv();
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test --ffi -vv --mt test_isBelowMax_zeros
    */
    function test_isBelowMax_zeros() public {
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;
        address borrower;
        ISilo.AccrueInterestInMemory accrueInMemory;

        vm.expectRevert();
        impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, accrueInMemory);
    }

    /*
    forge test --ffi -vvv --mt test_isBelowMax_noDebt
    */
    function test_isBelowMax_noDebt() public {
        address borrower;

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(borrower);

        vm.expectRevert(); // because configs are empty
        impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.Yes);
    }

    /*
    forge test --ffi -vv --mt test_isBelowMax_whenSolvent
    */
    function test_isBelowMax_whenSolvent() public {
        address borrower = makeAddr("borrower");

        _deposit(100, borrower);
        _depositForBorrow(100, address(1));
        _borrow(silo1.maxBorrow(borrower), borrower);

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(borrower);

        assertTrue(
            impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.Yes),
            "when borrow with maxBorrow will be below max LTV"
        );

        assertTrue(
            impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.No),
            "when borrow with maxBorrow will be below max LTV"
        );
    }

    /*
    forge test --ffi -vv --mt test_isBelowMax_whenSolventButWithdraw
    */
    function test_isBelowMax_whenSolventButWithdraw() public {
        address borrower = makeAddr("borrower");

        _deposit(100, borrower);
        _depositForBorrow(100, address(1));
        _borrow(silo1.maxBorrow(borrower), borrower);

        vm.prank(borrower);
        silo0.withdraw(2, borrower, borrower);

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(borrower);

        assertFalse(
            impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.Yes),
            "[AccrueInterestInMemory.Yes] because of withdraw we not longer below max LTV"
        );

        assertFalse(
            impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.No),
            "[AccrueInterestInMemory.No] because of withdraw we not longer below max LTV"
        );
    }

    /*
    forge test --ffi -vv --mt test_isBelowMax_whenNotSolvent
    */
    function test_isBelowMax_whenNotSolvent() public {
        address borrower = makeAddr("borrower");

        _deposit(100, borrower);
        _depositForBorrow(100, borrower);
        _borrow(silo1.maxBorrow(borrower), borrower);

        vm.warp(100 days);

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(borrower);

        assertTrue(
            impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.No),
            "without interest we still under max LTV"
        );

        assertFalse(
            impl.isBelowMaxLtv(collateralConfig, debtConfig, borrower, ISilo.AccrueInterestInMemory.Yes),
            "with interest we over max LTV"
        );
    }
}
