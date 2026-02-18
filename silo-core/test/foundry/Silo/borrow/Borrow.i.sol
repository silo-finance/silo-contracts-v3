// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ShareTokenDecimalsPowLib} from "../../_common/ShareTokenDecimalsPowLib.sol";
import {RevertingIRM} from "silo-core/test/foundry/_mocks/RevertingIRM.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc BorrowIntegrationTest
*/
contract BorrowIntegrationTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;
    using ShareTokenDecimalsPowLib for uint256;

    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        assertTrue(siloConfig.getConfig(address(silo0)).maxLtv != 0, "we need borrow to be allowed");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_replay_assertBORROWING_HSPOST_F
    this test test fix for maxBorrow when fractions
    */
    function test_replay_assertBORROWING_HSPOST_F() public {
        token0.setOnDemand(true);
        token1.setOnDemand(true);

        address borrower = address(this);

        //@audit-issue BORROWING_HSPOST_F: User borrowing maxBorrow should never revert
        // error -> NotEnoughLiquidity
        silo0.mint(11638058238813243150339, borrower);
        silo1.deposit(8533010, address(1));
        silo1.borrow(8256930, borrower, borrower);

        vm.warp(block.timestamp + 12);
        silo1.accrueInterest();
        vm.warp(block.timestamp + 7);

        silo1.borrow(silo1.maxBorrow(borrower), borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_all_zeros
    */
    function test_borrow_all_zeros() public {
        vm.expectRevert(ISilo.InputZeroShares.selector);
        silo0.borrow(0, address(0), address(0));
    }

    /*
    forge test -vv --ffi --mt test_borrow_zero_assets
    */
    function test_borrow_zero_assets() public {
        uint256 assets = 0;
        address borrower = address(1);

        vm.expectRevert(ISilo.InputZeroShares.selector);
        silo0.borrow(assets, borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_when_NotEnoughLiquidity
    */
    function test_borrow_when_NotEnoughLiquidity() public {
        uint256 assets = 1e18;
        address receiver = address(10);

        vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        silo0.borrow(assets, receiver, receiver);
    }

    /*
    forge test -vv --ffi --mt test_borrow_when_frontRun_NoCollateral
    */
    function test_borrow_when_frontRun_NoCollateral() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        // frontrun on other silo
        _deposit(assets, borrower);

        vm.expectRevert(ISilo.AboveMaxLtv.selector);
        silo0.borrow(assets, borrower, borrower);

        vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        silo1.borrow(assets, borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_onWrongSilo_for_receiver_no_collateral
    */
    function test_borrow_onWrongSilo_for_receiver_no_collateral() public {
        uint256 assets = 1e18;
        address borrower = makeAddr("borrower");

        _deposit(assets, makeAddr("depositor"));
        _deposit(assets, borrower, ISilo.CollateralType.Protected);

        uint256 borrowForReceiver = 1;

        // because we want to mint for receiver
        vm.expectRevert(abi.encodeWithSelector(IShareToken.AmountExceedsAllowance.selector));
        vm.prank(borrower);
        silo0.borrow(borrowForReceiver, borrower, makeAddr("receiver"));
    }

    /*
    forge test -vv --ffi --mt test_borrow_onWrongSilo_for_receiver_with_collateral
    */
    function test_borrow_onWrongSilo_for_receiver_with_collateral() public {
        uint256 assets = 1e18;
        address borrower = makeAddr("borrower");
        address receiver = makeAddr("receiver");

        _deposit(assets, receiver, ISilo.CollateralType.Protected);

        vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        vm.prank(borrower);
        silo0.borrow(1, borrower, receiver);
    }

    /*
    forge test -vv --ffi --mt test_borrow_revert_for_receiver_with_collateral
    */
    function test_borrow_revert_for_receiver_with_collateral() public {
        uint256 assets = 1e18;
        address borrower = makeAddr("borrower");
        address receiver = makeAddr("receiver");

        _depositForBorrow(assets, makeAddr("depositor"));
        _deposit(assets, receiver, ISilo.CollateralType.Protected);

        uint256 borrowForReceiver = 1;

        // because we want to mint for receiver
        vm.expectRevert(abi.encodeWithSelector(IShareToken.AmountExceedsAllowance.selector));
        vm.prank(borrower);
        silo1.borrow(borrowForReceiver, borrower, receiver);
    }

    /*
    forge test -vv --ffi --mt test_borrow_onWrongSilo_for_borrower
    */
    function test_borrow_onWrongSilo_for_borrower() public {
        uint256 assets = 1e18;
        address borrower = makeAddr("borrower");

        _deposit(assets, makeAddr("depositor"));
        _deposit(assets, borrower);

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, borrower, assets));

        vm.expectRevert(ISilo.AboveMaxLtv.selector);
        vm.prank(borrower);
        silo0.borrow(assets, borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_onWrongSilo_WithProtected
    */
    function test_borrow_onWrongSilo_WithProtected() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        _deposit(assets, borrower, ISilo.CollateralType.Protected);

        vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        silo0.borrow(assets, borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_onWrongSilo_WithCollateralAndProtected
    */
    function test_borrow_onWrongSilo_WithCollateralAndProtected() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        _deposit(assets * 2, borrower, ISilo.CollateralType.Protected);
        _deposit(assets, borrower);

        vm.expectRevert(ISilo.AboveMaxLtv.selector);
        silo0.borrow(assets, borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_BorrowNotPossible_withDebt
    */
    function test_borrow_BorrowNotPossible_withDebt() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        _depositForBorrow(assets, makeAddr("depositor"));
        _deposit(assets, borrower, ISilo.CollateralType.Protected);
        _borrow(1, borrower);

        vm.expectRevert(ISilo.BorrowNotPossible.selector);
        silo0.borrow(assets, borrower, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_frontRun_pass
    */
    function test_borrow_frontRun_pass() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        _depositForBorrow(assets, makeAddr("depositor"));
        _deposit(assets, borrower, ISilo.CollateralType.Protected);

        vm.prank(makeAddr("frontrunner"));
        _deposit(1, borrower);

        _borrow(12345, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_frontRun_transferShare
    */
    function test_borrow_frontRun_transferShare() public {
        uint256 assets = 1e18;
        address borrower = makeAddr("borrower");
        address frontrunner = makeAddr("frontrunner");

        _depositForBorrow(assets, makeAddr("depositor"));
        _deposit(assets, borrower, ISilo.CollateralType.Protected);

        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo1));

        _depositForBorrow(5, frontrunner);
        _depositForBorrow(3, frontrunner, ISilo.CollateralType.Protected);

        vm.prank(frontrunner);
        IShareToken(collateralShareToken).transfer(borrower, 5);
        vm.prank(frontrunner);
        IShareToken(protectedShareToken).transfer(borrower, 3);

        _borrow(12345, borrower); // frontrun does not work
    }

    /*
    forge test -vv --ffi --mt test_borrow_withTwoCollaterals
    */
    function test_borrow_withTwoCollaterals() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        _depositForBorrow(assets, makeAddr("depositor"));

        uint256 notCollateral = 123;
        _deposit(notCollateral, borrower);
        _deposit(assets, borrower, ISilo.CollateralType.Protected);

        vm.expectEmit(address(silo1));
        emit ISilo.CollateralTypeChanged(borrower);

        _borrow(12345, borrower);
    }

    /*
    forge test -vv --ffi --mt test_borrow_pass
    */
    function test_borrow_pass() public {
        uint256 depositAssets = 1e18;
        address borrower = makeAddr("Borrower");
        address depositor = makeAddr("Depositor");

        _depositForBorrow(depositAssets, depositor);
        _deposit(depositAssets, borrower);

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo0));

        uint256 maxBorrow = silo1.maxBorrow(borrower);
        uint256 maxBorrowShares = silo1.maxBorrowShares(borrower);

        assertEq(maxBorrow, 0.75e18 - 1, "invalid maxBorrow for two tokens");
        assertEq(maxBorrowShares, 0.75e18 - 1, "invalid maxBorrowShares for two tokens");

        uint256 borrowToMuch = maxBorrow + 2;
        // emit log_named_uint("borrowToMuch", borrowToMuch);

        vm.expectRevert(ISilo.AboveMaxLtv.selector);
        vm.prank(borrower);
        silo1.borrow(borrowToMuch, borrower, borrower);

        _borrow(maxBorrow, borrower);

        assertEq(
            IShareToken(debtShareToken).balanceOf(borrower),
            0,
            "expect borrower to NOT have debt in collateral silo"
        );
        assertEq(silo0.getDebtAssets(), 0, "expect collateral silo to NOT have debt");

        (protectedShareToken, collateralShareToken, debtShareToken) = siloConfig.getShareTokens(address(silo1));
        assertEq(
            IShareToken(debtShareToken).balanceOf(borrower), maxBorrow, "expect borrower to have debt in debt silo"
        );
        assertEq(silo1.getDebtAssets(), maxBorrow, "expect debt silo to have debt");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_borrow_twice
    */
    function test_borrow_twice() public {
        uint256 depositAssets = 1e18;
        address depositor = address(0x9876123);
        address borrower = address(0x22334455);

        _deposit(depositAssets, borrower);
        // deposit, so we can borrow
        _depositForBorrow(depositAssets * 2, depositor);

        (, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));
        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));

        assertEq(
            IShareToken(collateralShareToken).balanceOf(borrower),
            depositAssets.decimalsOffsetPow(),
            "expect borrower to have collateral"
        );

        _borrowTwoAssetsAssertions(borrower, debtShareToken, collateralShareToken);

        // _borrow(0.0001e18, borrower, ISilo.AboveMaxLtv.selector);
    }

    /*
    forge test -vv --ffi --mt test_borrow_scenarios
    */
    function test_borrow_scenarios() public {
        _borrow_scenarios();
    }

    /*
    forge test -vv --ffi --mt test_borrow_scenarios_revertingIRM_standardRevert
    */
    function test_borrow_scenarios_revertingIRM_standardRevert() public {
        address irm = address(new RevertingIRM(RevertingIRM.RevertReasons.StandardRevert));
        _mockIRM(silo0, irm);
        _mockIRM(silo1, irm);
        _borrow_scenarios();
    }

    /*
    forge test -vv --ffi --mt test_borrow_scenarios_revertingIRM_zeroDiv
    */
    function test_borrow_scenarios_revertingIRM_zeroDiv() public {
        address irm = address(new RevertingIRM(RevertingIRM.RevertReasons.ZeroDiv));
        _mockIRM(silo0, irm);
        _mockIRM(silo1, irm);
        _borrow_scenarios();
    }

    /*
    forge test -vv --ffi --mt test_borrow_scenarios_revertingIRM_underflow
    */
    function test_borrow_scenarios_revertingIRM_underflow() public {
        address irm = address(new RevertingIRM(RevertingIRM.RevertReasons.Underflow));
        _mockIRM(silo0, irm);
        _mockIRM(silo1, irm);
        _borrow_scenarios();
    }

    /*
    forge test -vv --ffi --mt test_borrow_scenarios_revertingIRM_overflow
    */
    function test_borrow_scenarios_revertingIRM_overflow() public {
        address irm = address(new RevertingIRM(RevertingIRM.RevertReasons.Overflow));
        _mockIRM(silo0, irm);
        _mockIRM(silo1, irm);
        _borrow_scenarios();
    }

    /*
    forge test -vv --ffi --mt test_borrow_scenarios_revertingIRM_customError
    */
    function test_borrow_scenarios_revertingIRM_customError() public {
        address irm = address(new RevertingIRM(RevertingIRM.RevertReasons.CustomError));
        _mockIRM(silo0, irm);
        _mockIRM(silo1, irm);
        _borrow_scenarios();
    }

    function _borrow_scenarios() private {
        uint256 depositAssets = 1e18;
        address borrower = address(0x22334455);
        address depositor = address(0x9876123);
        uint256 expectedLtv = 0.75e18;

        _deposit(depositAssets, borrower, ISilo.CollateralType.Collateral);

        // deposit, so we can borrow
        _depositForBorrow(100e18, depositor);
        assertEq(silo0.getLtv(borrower), 0, "no debt, so LT == 0 (silo0)");
        assertEq(silo1.getLtv(borrower), 0, "no debt, so LT == 0 (silo1)");

        uint256 maxBorrow = silo1.maxBorrow(borrower) + 1; // +1 to balance out underestimation

        _borrow(200e18, borrower, ISilo.NotEnoughLiquidity.selector);
        _borrow(maxBorrow * 2, borrower, ISilo.AboveMaxLtv.selector);
        _borrow(maxBorrow / 2, borrower);
        assertEq(
            silo0.getLtv(borrower), expectedLtv / 2, "borrow 50% of max, maxLTV is 75%, so LT == 37,5% (silo0)"
        );
        assertEq(
            silo1.getLtv(borrower), expectedLtv / 2, "borrow 50% of max, maxLTV is 75%, so LT == 37,5% (silo1)"
        );

        _borrow(200e18, borrower, ISilo.NotEnoughLiquidity.selector);
        _borrow(maxBorrow, borrower, ISilo.AboveMaxLtv.selector);
        _borrow(maxBorrow / 2, borrower);
        assertEq(silo0.getLtv(borrower), expectedLtv, "borrow 100% of max, so LT == 75% (silo0)");
        assertEq(silo1.getLtv(borrower), expectedLtv, "borrow 100% of max, so LT == 75% (silo1)");

        assertEq(silo0.maxBorrow(borrower), 0, "maxBorrow 0");
        assertTrue(silo0.isSolvent(borrower), "still isSolvent (silo0)");
        assertTrue(silo1.isSolvent(borrower), "still isSolvent (silo1)");

        _borrow(1, borrower, ISilo.AboveMaxLtv.selector);
    }

    /*
    forge test -vv --ffi --mt test_borrowShares_revertsOnZeroAssets
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_borrowShares_revertsOnZeroAssets_fuzz(uint256 _depositAmount, uint256 _forBorrow) public {
        vm.assume(_depositAmount < type(uint128).max);
        vm.assume(_depositAmount > _forBorrow);
        vm.assume(_forBorrow > 0);

        address borrower = makeAddr("Borrower");
        address depositor = makeAddr("depositor");

        _deposit(_depositAmount, borrower);
        _depositForBorrow(_forBorrow, depositor);

        vm.expectEmit(address(silo1));
        emit ISilo.CollateralTypeChanged(borrower);

        uint256 amount = _borrowShares(1, borrower);

        assertGt(amount, 0, "amount can never be 0");
    }

    function _borrow(uint256 _amount, address _borrower, bytes4 _revert) internal returns (uint256 shares) {
        vm.expectRevert(_revert);
        vm.prank(_borrower);
        shares = silo1.borrow(_amount, _borrower, _borrower);
    }

    function _borrowTwoAssetsAssertions(address _borrower, address _debtShareToken, address _collateralToken)
        private
    {
        uint256 maxLtv = 0.75e18;

        uint256 maxBorrow = silo0.maxBorrow(_borrower);
        assertEq(maxBorrow, 0, "maxBorrow should be 0, because this is where collateral is");

        maxBorrow = silo1.maxBorrow(_borrower);
        emit log_named_decimal_uint("maxBorrow #1", maxBorrow, 18);
        // -1 because of the fractions underestimation
        assertEq(maxBorrow, maxLtv - 1, "maxBorrow borrower can do, maxLTV is 75%");

        uint256 borrowAmount = maxBorrow / 2;
        emit log_named_decimal_uint("first borrow amount", borrowAmount, 18);

        uint256 convertToShares = silo1.convertToShares(borrowAmount, ISilo.AssetType.Debt);
        uint256 previewBorrowShares = silo1.previewBorrowShares(convertToShares);
        assertEq(previewBorrowShares, borrowAmount, "previewBorrowShares crosscheck");

        uint256 gotShares = _borrow(borrowAmount, _borrower);
        uint256 shareTokenCurrentDebt = maxLtv / 2;

        uint256 expectedShares = 1e18;
        expectedShares = expectedShares.decimalsOffsetPow();

        assertEq(
            IShareToken(_debtShareToken).balanceOf(_borrower),
            shareTokenCurrentDebt - 1,
            "expect borrower to have 1/2 of debt"
        );
        assertEq(
            IShareToken(_collateralToken).balanceOf(_borrower),
            expectedShares,
            "collateral silo: borrower has collateral"
        );
        assertEq(silo1.getDebtAssets(), shareTokenCurrentDebt - 1, "silo debt");
        assertEq(gotShares, shareTokenCurrentDebt - 1, "got debt shares");
        assertEq(gotShares, convertToShares, "convertToShares returns same result");
        assertEq(
            borrowAmount,
            silo1.convertToAssets(gotShares, ISilo.AssetType.Debt),
            "convertToAssets returns borrowAmount"
        );

        borrowAmount = silo1.maxBorrow(_borrower);
        emit log_named_decimal_uint("borrowAmount #2", borrowAmount, 18);
        assertEq(borrowAmount, maxLtv / 2 - 2, "borrow second time"); // -2 because of the fractions underestimation

        convertToShares = silo1.convertToShares(borrowAmount, ISilo.AssetType.Debt);
        gotShares = _borrow(borrowAmount, _borrower);

        assertEq(IShareToken(_debtShareToken).balanceOf(_borrower), maxLtv - 3, "debt silo: borrower has debt");
        assertEq(gotShares, maxLtv / 2 - 2, "got shares"); // -2 because of the fractions underestimation
        assertEq(silo1.getDebtAssets(), maxBorrow - 2, "debt silo: has debt"); // -2 because of the fractions underestimation
        assertEq(gotShares, convertToShares, "convertToShares returns same result (2)");
        assertEq(
            borrowAmount,
            silo1.convertToAssets(gotShares, ISilo.AssetType.Debt),
            "convertToAssets returns borrowAmount (2)"
        );

        // collateral silo
        (,, _debtShareToken) = siloConfig.getShareTokens(address(silo0));

        assertEq(
            IShareToken(_debtShareToken).balanceOf(_borrower), 0, "collateral silo: expect borrower NOT have debt"
        );

        assertEq(
            IShareToken(_collateralToken).balanceOf(_borrower),
            expectedShares,
            "collateral silo: borrower has collateral"
        );

        assertEq(silo0.getDebtAssets(), 0, "collateral silo: NO debt");

        assertTrue(silo0.isSolvent(_borrower), "still isSolvent (silo0)");
        assertTrue(silo1.isSolvent(_borrower), "still isSolvent (silo1)");
    }
}
