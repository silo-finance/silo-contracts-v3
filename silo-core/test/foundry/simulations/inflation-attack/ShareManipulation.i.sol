// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc ShareManipulationTest

    1. sergiey example is based on 70day period
    2. depositing and withdrawing does not change share/assets ration (I was not able to do that)

*/
contract ShareManipulationTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_collateral_ratio --gas-limit 40000000000

    in this test I try to break 1wei:1we ratio and I can not with reasonable amount of assets

    we need time to increasing ratio of asset:shares

    */
    function test_collateral_ratio() public {
        address borrower = makeAddr("borrower");
        address depositor = makeAddr("depositor");
        address depositor2 = makeAddr("depositor2");
        address depositor3 = makeAddr("depositor3");

        _deposit(1e18, borrower);
        _depositForBorrow(1e18, depositor);

        // when there are other users, results to change ratio is MUCH harder
        // I'm over gas limit with execution when I add this one user
        // because % are growing much much slower, I changes moving time in days, and after years I dog 1 wei diff.
        //        _depositForBorrow(100e18, makeAddr("any"));
        _borrow(0.75e18, borrower);

        uint256 precision = 1e18;
        // changing offset 1 -> 10 does not change much, it's basically higher precision, but numbers are the same.
        uint256 offset = 10 ** 0;

        // the higher number you check the faster we get result
        //        while (silo1.convertToAssets(precision * offset) == precision) {
        //            vm.warp(block.timestamp + 1);
        //        }

        // let's wait until user insolvent
        while (silo1.isSolvent(borrower)) {
            //            vm.warp(block.timestamp + 1 days);
            vm.warp(block.timestamp + 1 hours);
            silo1.accrueInterest(); // to boost %
        }

        emit log_named_uint("DIFF", silo1.convertToAssets(precision * offset));
        emit log_named_uint("DIFF", precision);
        emit log_named_decimal_uint("repay:", silo1.maxRepay(borrower), 18);
        emit log_named_uint("time:", block.timestamp);

        _printCollateralRatio(offset);

        uint256 ratioBefore = silo1.convertToAssets(precision * offset);
        uint256 moneySpend;
        uint256 _initial = 1e10; // changing initial amount does not affect ratio

        // so we can  max withdraw
        _depositForBorrow(0.9e18, depositor3);

        uint256 withdrawBefore = silo1.maxWithdraw(depositor);
        uint256 repayBefore = silo1.maxRepay(borrower);

        emit log_named_decimal_uint("maxWithdraw(depositor)", withdrawBefore, 18);
        emit log_named_decimal_uint("maxRepay(borrower)", repayBefore, 18);

        for (uint256 i; i < 1000; i++) {
            // time helps increase ratio because there are interests involve
            // if attacker will wait 1sec between iterations, attack will take ~2days
            // HOWEVER: with time ratio grows MOSTLY because of interest, not the tx
            //            vm.warp(block.timestamp + 1);

            // emit log_named_uint("#i", i);
            // emit log_named_decimal_uint("_initial", _initial, 18);

            uint256 depositAmount = (_initial % 10_000e18);

            _depositForBorrow(depositAmount, depositor2);
            // by leaving 1 wei you can change ratio by 1 per iteration
            // BUT you paying for it!
            _withdrawFromBorrow(depositAmount - 1, depositor2);
            moneySpend += (depositAmount - depositAmount + 1);

            _initial = silo1.getCollateralAssets();
        }

        emit log_named_uint("ratioBefore", ratioBefore);

        uint256 ratioDiff = silo1.convertToAssets(precision * offset) - ratioBefore;
        emit log_named_decimal_uint(">>>>>> ratio increased by", ratioDiff, 18);
        emit log_named_decimal_uint("moneySpend", moneySpend, 18);

        emit log_named_decimal_uint("maxRepay(borrower)", repayBefore, 18);
        emit log_named_decimal_uint("maxRepay(borrower)", silo1.maxRepay(borrower), 18);

        _repay(silo1.maxRepay(borrower), borrower);
        _printCollateralRatio(offset);

        // depositor2 was doing attack and he lost, he left 150K wei but he can withdraw only 78K wei after attack
        emit log_named_decimal_uint("maxWithdraw(depositor2)", silo1.maxWithdraw(depositor2), 18);
        emit log_named_decimal_uint("maxWithdraw(depositor3)", silo1.maxWithdraw(depositor3), 18);

        emit log_named_decimal_uint("maxWithdraw(depositor)", silo1.maxWithdraw(depositor), 18);
        emit log_named_decimal_uint(
            "maxWithdraw(depositor) diff", silo1.maxWithdraw(depositor) - withdrawBefore, 18
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_debt_ratio --gas-limit 40000000000
    */
    function test_debt_ratio() public {
        _depositForBorrow(3e18, makeAddr("depositor"));

        _deposit(1e18, makeAddr("borrower"));
        _deposit(1e18, makeAddr("borrower2"));
        _deposit(100, makeAddr("borrower3"));

        _borrow(0.75e18, makeAddr("borrower2"));
        _borrow(70, makeAddr("borrower3"));

        uint256 precision = 1e18;
        // changing offset 1 -> 10 does not change much, it's basically higher precision, but numbers are the same.
        uint256 offset = 10 ** 0;

        // the higher number you check the faster we get result
        //        while(silo1.previewBorrowShares(precision * offset) == precision) {
        //            vm.warp(block.timestamp + 1);
        //        }

        while (silo1.isSolvent(makeAddr("borrower2"))) {
            vm.warp(block.timestamp + 1 hours);
            // doing this will reduce total debt from
            // 850003201235794561 to
            // 850003201235761988 = 32573,
            // 32573 / 3201235794561 => 0.000001%
            // simply not worth it
            //            _borrowRepay();

            silo1.accrueInterest(); // to boost %
        }

        _borrow1wei();
        // return;

        assertGt(silo1.previewBorrowShares(precision * offset), precision, "require not to have 1:1 ratio");

        uint256 ratioBefore = silo1.previewBorrowShares(precision * offset);

        emit log_named_uint("DIFF", precision);
        emit log_named_uint("DIFF", ratioBefore);
        emit log_named_decimal_uint("repay:", silo1.maxRepay(makeAddr("borrower")), 18);
        emit log_named_uint("time:", block.timestamp);

        _printBorrowRatio();

        // uint256 moneySpend;
        // uint256 _initial = 1e10; // changing initial amount does not affect ratio

        uint256 withdrawBefore = silo1.maxWithdraw(makeAddr("depositor"));
        uint256 repayBefore = silo1.maxRepay(makeAddr("borrower"));

        emit log_named_decimal_uint("maxWithdraw(depositor)", withdrawBefore, 18);
        emit log_named_decimal_uint("maxRepay(borrower)", repayBefore, 18);
        emit log_named_decimal_uint("maxRepay(borrower2)", silo1.maxRepay(makeAddr("borrower2")), 18);
        emit log_named_decimal_uint("maxRepay(borrower3)", silo1.maxRepay(makeAddr("borrower3")), 18);

        // _repay(silo1.maxRepay(borrower), borrower);

        for (uint256 i; i < 30; i++) {
            // vm.warp(block.timestamp + 1);

            emit log_named_uint("#i", i);
            // emit log_named_decimal_uint("_initial", _initial, 18);

            _borrowRepay();
        }

        emit log_named_uint("ratioBefore", ratioBefore);
        emit log_named_uint("ratioNow   ", silo1.previewBorrowShares(precision * offset));

        uint256 ratioDiff = ratioBefore - silo1.previewBorrowShares(precision * offset);
        // how we decreasing and "where it goes"?
        // we repay MORE because of rounding, so every time attacker do this, he repay more
        // and this "more" is what other borrowers will not pay
        //
        emit log_named_decimal_uint("ratio DECREASED?? by", ratioDiff, 18);
        //        emit log_named_decimal_uint("moneySpend", moneySpend, 18);

        emit log_named_decimal_uint("BEFORE maxRepay(borrower)", repayBefore, 18);
        emit log_named_decimal_uint("AFTER maxRepay(borrower)", silo1.maxRepay(makeAddr("borrower")), 18);
        emit log_named_decimal_uint("AFTER maxRepay(borrower2)", silo1.maxRepay(makeAddr("borrower2")), 18);
        emit log_named_decimal_uint("AFTER maxRepay(borrower3)", silo1.maxRepay(makeAddr("borrower3")), 18);

        _repay(silo1.maxRepay(makeAddr("borrower")), makeAddr("borrower"));
        _printBorrowRatio();

        emit log_named_decimal_uint("maxWithdraw(depositor)", silo1.maxWithdraw(makeAddr("depositor")), 18);
        emit log_named_decimal_uint(
            "maxWithdraw(depositor) diff", silo1.maxWithdraw(makeAddr("depositor")) - withdrawBefore, 18
        );
    }

    function _borrow1wei() internal {
        address user = address(2);
        _depositForBorrow(100, user);
        _deposit(3, user);
        _borrow(1, user);

        (,, address debtShare) = siloConfig.getShareTokens(address(silo1));
        emit log_named_decimal_uint("1 wei == shares:", IShareToken(debtShare).balanceOf(user), 18);
        emit log_named_decimal_uint("AFTER maxRepay(user)", silo1.maxRepay(user), 18);
    }

    function _borrowRepay() internal {
        uint256 _amount = silo1.getDebtAssets();
        if (_amount == 0) _amount = 1;

        // vm.warp(block.timestamp + 1);

        // emit log_named_decimal_uint("_initial", _initial, 18);

        uint256 borrowAmount = (_amount % 0.7e18);

        _borrow(borrowAmount, makeAddr("borrower"));

        uint256 toRepay = silo1.maxRepay(makeAddr("borrower")) - 1;
        emit log_named_decimal_uint("borrowAmount", borrowAmount, 18);
        emit log_named_decimal_uint("toRepay", toRepay, 18);

        _repay(toRepay, makeAddr("borrower"));

        (,, address debtShare) = siloConfig.getShareTokens(address(silo1));
        emit log_named_decimal_uint("toRepay shares #1", IShareToken(debtShare).balanceOf(makeAddr("borrower")), 18);
        //        _repay(2, makeAddr("borrower"));
        //        emit log_named_decimal_uint("toRepay shares #2", IShareToken(debtShare).balanceOf(makeAddr("borrower")), 18);

        _printBorrowRatio();
    }

    function _printBorrowRatio() internal {
        (,, address debtShare) = siloConfig.getShareTokens(address(silo1));
        emit log("---------");
        emit log_named_uint("[silo1] debt share totalSupply ", IShareToken(debtShare).totalSupply());
        emit log_named_uint("[silo1] debt asset total ", silo1.getDebtAssets());
        emit log_named_uint(
            "[silo1] share balanceOf(borrower) ", IShareToken(debtShare).balanceOf(makeAddr("borrower"))
        );
        emit log_named_uint("[silo1] silo1.maxRepay(borrower) ", silo1.maxRepay(makeAddr("borrower")));
        emit log_named_uint(
            "[silo1] share balanceOf(borrower2) ", IShareToken(debtShare).balanceOf(makeAddr("borrower2"))
        );
        emit log_named_uint("[silo1] silo1.maxRepay(borrower2) ", silo1.maxRepay(makeAddr("borrower2")));
        emit log_named_uint(
            "[silo1] share balanceOf(borrower3) ", IShareToken(debtShare).balanceOf(makeAddr("borrower3"))
        );
        emit log_named_uint("[silo1] silo1.maxRepay(borrower3) ", silo1.maxRepay(makeAddr("borrower3")));

        emit log_named_decimal_uint("[silo1] 1e18 share =", silo1.previewBorrowShares(1e18), 18);
        emit log_named_uint("[silo1] 1 share =", silo1.previewBorrowShares(1));
        emit log("---------");
    }

    function _printCollateralRatio(uint256 _offset) internal {
        emit log_named_uint("[silo1] time", block.timestamp);
        emit log_named_uint("[silo1] getCollateralAssets", silo1.getCollateralAssets());
        emit log_named_uint("[silo1] 1 collateral share =", silo1.convertToAssets(1));
        emit log_named_uint("[silo1] 1e18 collateral share =", silo1.convertToAssets(1e18 * _offset));
    }
}
