// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {MintableToken} from "../_common/MintableToken.sol";
import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";
import {SiloFixture, SiloConfigOverride} from "../_common/fixtures/SiloFixture.sol";

/*
    forge test -vv --ffi --mc BorrowImmediateBadDebtTest

    conclusions:
    - the biggest the decimals, the more precise LTV and user will became insolvent faster
    - the smallest the borrow amount eg 1 wei, the longer user stay solvent
    - in order to create insolvency after 1 sec, with max utilization, we need to borrow:
      - 0.75 (8 decimals) - for less decimals we need to use 1 token or above
      - or 0.000075 (18 decimals)

    any "fixes" for it?
    - any check for future LTV will not work
    - minimal borrow? eg one token? this will definitely increase cost of spamming and minimise cost of "cleanup liquidations"
      but at the same time it will add more complexity to eg withdraw, repay.

    I think we need to deal with it. Also this case can be created by almost full repay,
    when user repay eg based on amount not based on shares, and it will leave some dust as debt.
*/
contract BorrowImmediateBadDebtTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;
    using Strings for uint256;

    ISiloConfig siloConfig;

    /*
        forge test -vv --ffi --mt test_immediateBadDebt_1wei_
    */
    function test__skip__immediateBadDebt_1wei_18_18() public {
        _immediateBadDebt_1wei(18, 18);
    }

    function test__skip__immediateBadDebt_1wei_6_6() public {
        _immediateBadDebt_1wei(6, 6);
    }

    function _immediateBadDebt_1wei(uint8 _decimals0, uint8 _decimals1) private {
        _setUp(_decimals0, _decimals1);

        uint256 assets = 1;
        address borrower = address(this);

        _depositForBorrow(assets, makeAddr("depositor"));

        _deposit(2, borrower);
        uint256 borrowShares = _borrow(assets, borrower);

        uint256 ltvBefore = silo1.getLtv(borrower);
        assertEq(ltvBefore, 0.5e18, "LTV is 50%");

        ISilo.UtilizationData memory data = silo1.utilizationData();

        assertEq(data.debtAssets * 1e18 / data.collateralAssets, 1e18, "100% utilization");

        uint256 solvencyTime = 8 days;
        vm.warp(block.timestamp + solvencyTime);
        emit log_named_decimal_uint("LTV after solvencyTime", silo1.getLtv(borrower), 18);
        assertTrue(silo1.isSolvent(borrower));

        uint256 insolventTime = solvencyTime + 1 days;
        vm.warp(block.timestamp + 1 days);
        emit log_named_decimal_uint("LTV after some time", silo1.getLtv(borrower), 18);

        assertTrue(
            !silo1.isSolvent(borrower),
            string.concat("it takes over ", (solvencyTime / 60 / 60 / 24).toString(), " days to be insolvent")
        );

        vm.warp(block.timestamp + 365 days - insolventTime);

        emit log_named_decimal_uint("[1y] LTV after 1y", silo1.getLtv(borrower), 18);
        emit log_named_uint("[1y] current debt", silo1.previewRepayShares(borrowShares));
        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrower);

        emit log_named_uint("[1y] collateralToLiquidate", collateralToLiquidate);
        emit log_named_uint("[1y] debtToRepay", debtToRepay);

        assertEq(silo1.getLtv(borrower), ltvBefore * 100, "[1y] LTV x100");

        vm.warp(block.timestamp + 365 days);

        emit log_named_decimal_uint("[2y] LTV after 2y", silo1.getLtv(borrower), 18);
        emit log_named_uint("[2y] current debt", silo1.previewRepayShares(borrowShares));
        (collateralToLiquidate, debtToRepay,) = partialLiquidation.maxLiquidation(borrower);

        emit log_named_uint("[2y] collateralToLiquidate", collateralToLiquidate);
        emit log_named_uint("[2y] debtToRepay", debtToRepay);

        assertEq(silo1.getLtv(borrower), ltvBefore * 200, "[2y] LTV x200");
    }

    function _immediateBadDebt_80wei(uint8 _decimals0, uint8 _decimals1) private {
        _setUp(_decimals0, _decimals1);

        uint256 assets = 75;
        address borrower = address(this);

        _depositForBorrow(assets, makeAddr("depositor"));

        _deposit(100, borrower);
        uint256 borrowShares = _borrow(assets, borrower);

        vm.prank(borrower);
        ISilo collateralSilo = silo0;
        collateralSilo.withdraw(11, borrower, borrower); // bring LTV just below LT

        uint256 ltvBefore = silo1.getLtv(borrower);
        assertEq(ltvBefore, 842696629213483147, "LTV is just below LT");

        ISilo.UtilizationData memory data = silo1.utilizationData();

        assertEq(data.debtAssets * 1e18 / data.collateralAssets, 1e18, "100% utilization");

        uint256 solvencyTime = 1 days;
        vm.warp(block.timestamp + solvencyTime);
        emit log_named_decimal_uint("LTV after solvencyTime", silo1.getLtv(borrower), 18);
        assertTrue(silo1.isSolvent(borrower), "user must be still solvent");

        uint256 insolventTime = solvencyTime + 1 days;
        vm.warp(block.timestamp + 1 days);
        emit log_named_decimal_uint("LTV after some time", silo1.getLtv(borrower), 18);

        assertTrue(
            !silo1.isSolvent(borrower),
            string.concat("it takes over ", (solvencyTime / 60 / 60 / 24).toString(), " days to be insolvent")
        );

        vm.warp(block.timestamp + 365 days - insolventTime);

        emit log_named_decimal_uint("[1y] LTV after 1y", silo1.getLtv(borrower), 18);
        emit log_named_uint("[1y] current debt", silo1.previewRepayShares(borrowShares));
        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrower);

        emit log_named_uint("[1y] collateralToLiquidate", collateralToLiquidate);
        emit log_named_uint("[1y] debtToRepay", debtToRepay); // 2 tokens: 7574,

        assertEq(silo1.getLtv(borrower), 85.101123595505617978e18, "[1y] LTV 850%");

        vm.warp(block.timestamp + 365 days);

        emit log_named_decimal_uint("[2y] LTV after 2y", silo1.getLtv(borrower), 18);
        emit log_named_uint("[2y] current debt", silo1.previewRepayShares(borrowShares));
        (collateralToLiquidate, debtToRepay,) = partialLiquidation.maxLiquidation(borrower);

        emit log_named_uint("[2y] collateralToLiquidate", collateralToLiquidate);
        emit log_named_uint("[2y] debtToRepay", debtToRepay); // 2 tokens: 15074

        assertEq(silo1.getLtv(borrower), 169.370786516853932585e18, "[2y] LTV 1600%");
    }

    function _immediateBadDebt_oneSecond(uint8 _decimals, uint256 _collateral) private {
        _setUp(_decimals, _decimals);

        uint256 one = 10 ** _decimals;
        uint256 assets = one * 75 / 100;
        address borrower = address(this);

        _depositForBorrow(assets, makeAddr("depositor"));

        uint256 toBorrow = _collateral * 75 / 100;
        emit log_named_decimal_uint("toBorrow for 1 sec", toBorrow, _decimals);

        _deposit(_collateral, borrower);
        _borrow(toBorrow, borrower);

        ISilo collateralSilo = silo0;
        emit log_named_decimal_uint("maxWithdraw", collateralSilo.maxWithdraw(borrower), _decimals);

        vm.prank(borrower);
        // d / c = 0.85 => c = d / 0.85
        uint256 toWithdraw = _collateral - toBorrow * one / ((one * 85) / 100) - 1;
        emit log_named_decimal_uint("toWithdraw", toWithdraw, _decimals);
        collateralSilo.withdraw(toWithdraw, borrower, borrower); // bring LTV just below LT

        uint256 solvencyTime = 1;
        vm.warp(block.timestamp + solvencyTime);
        emit log_named_decimal_uint("LTV after solvencyTime", silo1.getLtv(borrower), 18);
        assertTrue(!silo1.isSolvent(borrower), "user insolvent after 1 sec");
    }

    function _setUp(uint8 _decimals0, uint8 _decimals1) private {
        token0 = new MintableToken(_decimals0);
        token1 = new MintableToken(_decimals1);

        SiloFixture siloFixture = new SiloFixture();
        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);

        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);
    }
}
