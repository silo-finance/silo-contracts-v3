// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc LiquidationCallTest
*/
contract LiquidationCallTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;
    using SafeCast for uint256;

    address constant DEPOSITOR = address(1);
    address constant BORROWER = address(0x123);
    uint256 constant COLLATERAL = 10e18;
    uint256 constant COLLATERAL_FOR_BORROW = 8e18;
    uint256 constant DEBT = 7.5e18;

    ISiloConfig siloConfig;
    uint256 debtStart;

    ISiloConfig.ConfigData silo0Config;
    ISiloConfig.ConfigData silo1Config;

    error SenderNotSolventAfterTransfer();

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        _depositForBorrow(COLLATERAL_FOR_BORROW, DEPOSITOR);
        emit log_named_decimal_uint("COLLATERAL_FOR_BORROW", COLLATERAL_FOR_BORROW, 18);

        _deposit(COLLATERAL, BORROWER);
        _borrow(DEBT, BORROWER);
        emit log_named_decimal_uint("DEBT", DEBT, 18);
        debtStart = block.timestamp;

        assertEq(token0.balanceOf(address(this)), 0, "liquidation should have no collateral");
        assertEq(token0.balanceOf(address(silo0)), COLLATERAL, "silo0 has borrower collateral");
        assertEq(token1.balanceOf(address(silo1)), 0.5e18, "silo1 has only 0.5 debt token (8 - 7.5)");

        silo0Config = siloConfig.getConfig(address(silo0));
        silo1Config = siloConfig.getConfig(address(silo1));

        assertEq(silo0Config.liquidationFee, 0.05e18, "liquidationFee0");
        assertEq(silo1Config.liquidationFee, 0.025e18, "liquidationFee1");
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_UnexpectedCollateralToken
    */
    function test_liquidationCall_UnexpectedCollateralToken() public {
        uint256 maxDebtToCover = 1;
        bool receiveSToken;

        vm.expectRevert(IPartialLiquidation.UnexpectedCollateralToken.selector);
        partialLiquidation.liquidationCall(address(token1), address(token1), BORROWER, maxDebtToCover, receiveSToken);

        vm.expectRevert(IPartialLiquidation.UnexpectedCollateralToken.selector);
        partialLiquidation.liquidationCall(address(token1), address(token0), BORROWER, maxDebtToCover, receiveSToken);
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_UnexpectedDebtToken
    */
    function test_liquidationCall_UnexpectedDebtToken() public {
        uint256 maxDebtToCover = 1;
        bool receiveSToken;

        vm.expectRevert(IPartialLiquidation.UnexpectedDebtToken.selector);
        partialLiquidation.liquidationCall(address(token0), address(token0), BORROWER, maxDebtToCover, receiveSToken);
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_UserIsSolvent_whenUserSolvent
    */
    function test_liquidationCall_UserIsSolvent_whenUserSolvent() public {
        uint256 maxDebtToCover = 1e18;
        bool receiveSToken;

        vm.expectRevert(IPartialLiquidation.UserIsSolvent.selector);

        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, maxDebtToCover, receiveSToken);
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_revert_noDebt
    */
    function test_liquidationCall_revert_noDebt() public {
        address userWithoutDebt = address(1);
        uint256 maxDebtToCover = 1e18;
        bool receiveSToken;

        ISiloConfig.ConfigData memory debt;

        (, debt) = siloConfig.getConfigsForSolvency(userWithoutDebt);

        assertTrue(debt.silo == address(0), "we need user without debt for this test");

        vm.expectRevert(IPartialLiquidation.UserIsSolvent.selector);

        partialLiquidation.liquidationCall(
            address(token0), address(token1), userWithoutDebt, maxDebtToCover, receiveSToken
        );

        _liquidationModuleDoNotHaveTokens();
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_self
    */
    function test_liquidationCall_self() public {
        uint256 maxDebtToCover = 1e18;
        bool receiveSToken;

        token1.mint(BORROWER, maxDebtToCover);
        vm.prank(BORROWER);
        token1.approve(address(partialLiquidation), maxDebtToCover);

        assertTrue(silo0.isSolvent(BORROWER), "BORROWER solvent");

        vm.expectRevert(IPartialLiquidation.UserIsSolvent.selector);
        vm.prank(BORROWER);
        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, maxDebtToCover, receiveSToken);

        _liquidationModuleDoNotHaveTokens();
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_revertWhenNoCollateral
    */
    function test_liquidationCall_revertWhenNoCollateral() public {
        token0.setOnDemand(true);
        token1.setOnDemand(true);

        vm.warp(block.timestamp + 365 days);

        uint256 ltv = SILO_LENS.getLtv(silo0, BORROWER);
        assertGt(ltv, 1e18, "expect bad debt for this test");

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);
        assertGt(collateralToLiquidate, 0, "expect any collateral to liquidate");
        assertLt(collateralToLiquidate, debtToRepay, "price is 1:1 os the goal is to get 0 collateral and some debt");

        partialLiquidation.liquidationCall(
            address(token0), address(token1), BORROWER, collateralToLiquidate, false /* receiveSToken */
        );

        assertTrue(!silo0.isSolvent(BORROWER), "BORROWER should be insolvent");

        (collateralToLiquidate, debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);
        assertEq(collateralToLiquidate, 0, "expect no collateral to liquidate");
        assertGt(debtToRepay, 0, "expect some debt to repay");

        // we have NoCollateralToLiquidate error for this, but ReturnZeroShares is generate as first one
        vm.expectRevert(ISilo.ReturnZeroShares.selector);
        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, 1, false /* receiveSToken */ );
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_partial
    */
    function test_liquidationCall_partial() public {
        uint256 maxDebtToCover = 1e5;

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(address(silo1));
        ISiloConfig.ConfigData memory debtConfig = siloConfig.getConfig(address(silo0));

        (, uint64 interestRateTimestamp0,,,) = silo0.getSiloStorage();
        (, uint64 interestRateTimestamp1,,,) = silo1.getSiloStorage();

        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(BORROWER);

        assertEq(collateralToLiquidate, 0, "no collateralToLiquidate yet");
        assertEq(debtToRepay, 0, "no debtToRepay yet");
        assertTrue(!sTokenRequired, "sTokenRequired NOT required");

        emit log_named_decimal_uint("[test] LTV", silo1.getLtv(BORROWER), 16);

        // move forward with time so we can have interests
        uint256 timeForward = 7 days;
        vm.warp(block.timestamp + timeForward);

        (collateralToLiquidate, debtToRepay, sTokenRequired) = partialLiquidation.maxLiquidation(BORROWER);
        assertGt(collateralToLiquidate, 0, "expect collateralToLiquidate");
        assertGt(debtToRepay, maxDebtToCover, "expect debtToRepay");
        assertTrue(!sTokenRequired, "sTokenRequired NOT required");
        emit log_named_decimal_uint("[test] max debtToRepay", debtToRepay, 18);
        emit log_named_decimal_uint("[test] maxDebtToCover", maxDebtToCover, 18);

        vm.expectCall(address(silo0), abi.encodeWithSelector(ISilo.accrueInterest.selector));
        vm.expectCall(address(silo1), abi.encodeWithSelector(ISilo.accrueInterest.selector));

        vm.expectCall(
            address(debtConfig.interestRateModel),
            abi.encodeWithSelector(IInterestRateModel.getCompoundInterestRateAndUpdate.selector)
        );
        vm.expectCall(
            address(collateralConfig.interestRateModel),
            abi.encodeWithSelector(IInterestRateModel.getCompoundInterestRateAndUpdate.selector)
        );

        emit log_named_decimal_uint("[test] LTV after interest", silo1.getLtv(BORROWER), 16);
        assertEq(silo1.getLtv(BORROWER), 89_1188467990720448, "LTV after interest");
        assertLt(silo1.getLtv(BORROWER), 0.9e18, "expect LTV to be below dust level");
        assertFalse(silo1.isSolvent(BORROWER), "expect BORROWER to be insolvent");

        token1.mint(address(this), 2 ** 128);
        token1.approve(address(partialLiquidation), maxDebtToCover);

        // uint256 collateralWithFee = maxDebtToCover + 0.05e5; // too deep

        {
            // too deep
            // repay debt liquidator -> hook
            vm.expectCall(
                address(token1),
                abi.encodeWithSelector(
                    IERC20.transferFrom.selector, address(this), address(partialLiquidation), maxDebtToCover
                )
            );

            // repay debt hook -> silo
            vm.expectCall(
                address(token1),
                abi.encodeWithSelector(
                    IERC20.transferFrom.selector, address(partialLiquidation), address(silo1), maxDebtToCover
                )
            );

            // collateral with fee from silo to liquidator
            vm.expectCall(
                address(token0),
                abi.encodeWithSelector(IERC20.transfer.selector, address(this), maxDebtToCover + 0.05e5)
            );

            (uint256 withdrawAssetsFromCollateral, uint256 repayDebtAssets) = partialLiquidation.liquidationCall(
                address(token0), address(token1), BORROWER, maxDebtToCover, false /* receiveSToken */
            );

            emit log_named_decimal_uint("[test] withdrawAssetsFromCollateral", withdrawAssetsFromCollateral, 18);
            emit log_named_decimal_uint("[test] repayDebtAssets", repayDebtAssets, 18);
        }

        {
            // too deep
            emit log_named_decimal_uint("[test] LTV after small liquidation", silo1.getLtv(BORROWER), 16);
            assertEq(silo1.getLtv(BORROWER), 89_1188467990719805, "LTV after small liquidation");
            assertGt(silo1.getLtv(BORROWER), 0, "expect user to be still insolvent after small partial liquidation");
            assertTrue(!silo1.isSolvent(BORROWER), "expect BORROWER to be insolvent after small partial liquidation");

            assertEq(
                token0.balanceOf(address(this)), maxDebtToCover + 0.05e5, "liquidator should get collateral + 5% fee"
            );
            assertEq(
                token0.balanceOf(address(silo0)),
                COLLATERAL - (maxDebtToCover + 0.05e5),
                "silo collateral should be transfer to liquidator"
            );
            assertEq(token1.balanceOf(address(silo1)), 0.5e18 + maxDebtToCover, "debt token should be repaid");

            assertEq(silo0.getCollateralAssets(), COLLATERAL - (maxDebtToCover + 0.05e5), "total collateral");
            assertEq(silo1.getDebtAssets(), 8e18 + 911884679907104475, "debt token + interest");
        }

        {
            // too deep
            (, uint64 interestRateTimestamp0After,,,) = silo0.getSiloStorage();
            (, uint64 interestRateTimestamp1After,,,) = silo1.getSiloStorage();

            assertEq(interestRateTimestamp0 + timeForward, interestRateTimestamp0After, "interestRateTimestamp #0");
            assertEq(interestRateTimestamp1 + timeForward, interestRateTimestamp1After, "interestRateTimestamp #1");

            (collateralToLiquidate, debtToRepay, sTokenRequired) = partialLiquidation.maxLiquidation(BORROWER);
            assertGt(collateralToLiquidate, 0, "expect collateralToLiquidate after partial liquidation");
            assertGt(debtToRepay, 0, "expect debtToRepay after partial liquidation");
            assertTrue(!sTokenRequired, "sTokenRequired NOT required");

            token1.approve(address(partialLiquidation), debtToRepay);

            // repay debt liquidator -> hook
            vm.expectCall(
                address(token1),
                abi.encodeWithSelector(
                    IERC20.transferFrom.selector, address(this), address(partialLiquidation), 6_413645132946301397
                )
            );

            // repay debt hook -> silo
            vm.expectCall(
                address(token1),
                abi.encodeWithSelector(
                    IERC20.transferFrom.selector, address(partialLiquidation), address(silo1), 6_413645132946301397
                )
            );

            // collateral with fee from silo to liquidator
            vm.expectCall(
                address(token0), abi.encodeWithSelector(IERC20.transfer.selector, address(this), 6_734327389593616466)
            );

            vm.expectEmit(true, true, true, true, address(partialLiquidation));
            emit IPartialLiquidation.LiquidationCall(
                address(this), address(silo1), BORROWER, 6_413645132946301397, 6_734327389593616466, false
            );

            (uint256 withdrawAssetsFromCollateral, uint256 repayDebtAssets) = partialLiquidation.liquidationCall(
                address(token0), address(token1), BORROWER, 2 ** 128, false /* receiveSToken */
            );

            emit log_named_decimal_uint("[test] withdrawAssetsFromCollateral2", withdrawAssetsFromCollateral, 18);
            emit log_named_decimal_uint("[test] repayDebtAssets2", repayDebtAssets, 18);

            emit log_named_decimal_uint("[test] LTV after max liquidation", silo1.getLtv(BORROWER), 16);
            assertGt(silo1.getLtv(BORROWER), 0, "expect some LTV after partial liquidation");
            assertTrue(silo1.isSolvent(BORROWER), "expect BORROWER to be solvent");
        }

        _liquidationModuleDoNotHaveTokens();
    }

    /*
    forge test -vv --ffi --mt test_liquidationCall_FullLiquidationRequired
    */
    function test_liquidationCall_FullLiquidationRequired() public {
        assertEq(token1.balanceOf(address(silo1)), silo1.getLiquidity(), "without interest liquidity match balanceOf");

        // move forward with time so we can have interests

        for (uint256 i; i < 7; i++) {
            _timeForwardAndDebug(1 days);
        }

        assertLt(silo1.getLtv(BORROWER), 1e18, "expect insolvency, but not bad debt");
        assertGt(silo1.getLtv(BORROWER), 0.98e18, "expect hi LTV so we force full liquidation");

        (, uint256 debtToRepay, bool sTokenRequired) = partialLiquidation.maxLiquidation(BORROWER);

        assertTrue(!sTokenRequired, "sTokenRequired NOT required");
        assertGt(debtToRepay, COLLATERAL_FOR_BORROW, "check for 0 liquidity");
        assertEq(silo1.getLiquidity(), 0, "no liquidity because what was available is less than debt with interest");
        assertEq(debtToRepay, silo1.getDebtAssets(), "debtToRepay is max debt when we forcing full liquidation");

        uint256 maxDebtToCover = debtToRepay - 1; // -1 to check if tx reverts with FullLiquidationRequired
        bool receiveSToken;

        vm.expectRevert(IPartialLiquidation.FullLiquidationRequired.selector);
        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, maxDebtToCover, receiveSToken);

        _liquidationModuleDoNotHaveTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_badDebt_partial
    */
    function test_liquidationCall_badDebt_partial() public {
        uint256 maxDebtToCover = 100e18;
        bool receiveSToken;

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(address(silo0));
        ISiloConfig.ConfigData memory debtConfig = siloConfig.getConfig(address(silo1));

        (, uint64 interestRateTimestamp0,,,) = silo0.getSiloStorage();
        (, uint64 interestRateTimestamp1,,,) = silo1.getSiloStorage();

        // move forward with time so we can have interests

        uint256 timeForward = 30 days;
        vm.warp(block.timestamp + timeForward);
        // expected debt should grow from 7.5 => ~70
        assertGt(silo0.getLtv(BORROWER), 1e18, "expect bad debt");

        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(BORROWER);

        assertTrue(!sTokenRequired, "sTokenRequired NOT required");
        assertEq(
            collateralToLiquidate,
            COLLATERAL - 2,
            "expect full collateralToLiquidate on bad debt (-2 underestimation)"
        );
        assertGt(debtToRepay, DEBT, "debtToRepay must be higher that original");

        uint256 interest = 61_643835616429440000;
        assertEq(debtToRepay - DEBT, interest, "interests on debt");

        vm.expectCall(address(silo0), abi.encodeWithSelector(ISilo.accrueInterest.selector));
        vm.expectCall(
            address(debtConfig.interestRateModel),
            abi.encodeWithSelector(IInterestRateModel.getCompoundInterestRateAndUpdate.selector)
        );
        vm.expectCall(
            address(collateralConfig.interestRateModel),
            abi.encodeWithSelector(IInterestRateModel.getCompoundInterestRateAndUpdate.selector)
        );

        token1.mint(address(this), maxDebtToCover);
        token1.approve(address(partialLiquidation), maxDebtToCover);

        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, maxDebtToCover, receiveSToken);

        assertTrue(silo0.isSolvent(BORROWER), "user is solvent after liquidation");
        assertTrue(silo1.isSolvent(BORROWER), "user is solvent after liquidation");
        assertEq(silo1.getLtv(BORROWER), 0, "user has no debt");

        assertEq(debtConfig.daoFee, 0.15e18, "just checking on daoFee");
        assertEq(debtConfig.deployerFee, 0.1e18, "just checking on deployerFee");

        {
            // too deep
            uint256 daoAndDeployerRevenue = interest * (0.15e18 + 0.1e18) / 1e18; // dao fee + deployer fee

            assertEq(
                token0.balanceOf(address(this)),
                COLLATERAL,
                "liquidator should get all borrower collateral, no fee because of bad debt"
            );

            assertEq(token0.balanceOf(address(silo0)), 0, "all silo collateral should be transfer to liquidator");
            assertEq(silo0.getCollateralAssets(), 0, "total collateral == 0");

            assertEq(
                token1.balanceOf(address(silo1)),
                0.5e18 + 7.5e18 + interest,
                "silo has debt token fully repay, debt deposit + interest"
            );
            assertEq(
                silo1.getCollateralAssets(),
                0.5e18 + 7.5e18 + interest - daoAndDeployerRevenue,
                "borrowed token + interest"
            );

            assertEq(
                token1.balanceOf(address(this)),
                100e18 - (7.5e18 + interest),
                "liquidator did not used all the tokens"
            );
        }

        /*
          _totalCollateral.assets before %   8000000000000000000
          _totalDebt.assets before %         7500000000000000000

          _totalCollateral.assets %         54232876712322080000 (8 + accruedInterest - daoAndDeployerRevenue)
          _totalDebt.assets %               69143835616429440000 (7.5 + all interest)

          totalFees (daoAndDeployerRevenue) %  15410958904107360000
          accruedInterest %                 61643835616429440000
        */

        {
            // too deep
            (, uint64 interestRateTimestamp0After,,,) = silo0.getSiloStorage();
            (, uint64 interestRateTimestamp1After,,,) = silo1.getSiloStorage();

            assertEq(interestRateTimestamp0 + timeForward, interestRateTimestamp0After, "interestRateTimestamp #0");
            assertEq(interestRateTimestamp1 + timeForward, interestRateTimestamp1After, "interestRateTimestamp #1");
        }

        _liquidationModuleDoNotHaveTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_badDebt_full_withToken
    */
    function test_liquidationCall_badDebt_full_withToken() public {
        bool receiveSToken;
        address liquidator = makeAddr("liquidator");

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, liquidator, 10e18));

        _liquidationCall_badDebt_full(receiveSToken);

        assertEq(
            token0.balanceOf(liquidator), 10e18, "liquidator should get all collateral because of full liquidation"
        );
        assertEq(silo0.getCollateralAssets(), 0, "total collateral");
        assertEq(token0.balanceOf(address(silo0)), 0, "silo collateral should be transfer to liquidator");

        _liquidationModuleDoNotHaveTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_badDebt_full_withSToken
    */
    function test_liquidationCall_badDebt_full_withSToken() public {
        bool receiveSToken = true;
        uint256 collateralSharesToLiquidate = 10e18 * SiloMathLib._DECIMALS_OFFSET_POW;
        address liquidator = makeAddr("liquidator");

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(BORROWER);

        // IERC20(debtConfig.token).safeTransferFrom(msg.sender, address(this), repayDebtAssets);
        vm.expectCall(
            debtConfig.token,
            abi.encodeWithSelector(IERC20.transferFrom.selector, liquidator, address(partialLiquidation), 1e20)
        );

        // ISilo(debtConfig.silo).repay(repayDebtAssets, _borrower);
        vm.expectCall(
            debtConfig.token,
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(partialLiquidation), address(silo1), 1e20)
        );

        // shares -> liquidator (because of receive sToken)
        vm.expectCall(
            collateralConfig.collateralShareToken,
            abi.encodeWithSelector(
                IShareToken.forwardTransferFromNoChecks.selector, BORROWER, liquidator, collateralSharesToLiquidate
            )
        );

        _liquidationCall_badDebt_full(receiveSToken);

        assertEq(token0.balanceOf(liquidator), 0, "liquidator should not have collateral, because of sToken");
        assertEq(silo0.getCollateralAssets(), COLLATERAL, "silo still has collateral assets, because of sToken");
        assertEq(token0.balanceOf(address(silo0)), COLLATERAL, "silo still has collateral balance, because of sToken");

        _liquidationModuleDoNotHaveTokens();
    }

    function _liquidationCall_badDebt_full(bool _receiveSToken) internal {
        uint256 maxDebtToCover = 100e18;
        address liquidator = makeAddr("liquidator");

        // move forward with time so we can have interests

        uint256 timeForward = 50 days;
        vm.warp(block.timestamp + timeForward);

        uint256 maxRepay = silo1.maxRepay(BORROWER);

        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(BORROWER);

        assertTrue(!sTokenRequired, "sTokenRequired NOT required");
        assertEq(
            collateralToLiquidate,
            COLLATERAL - 2,
            "expect full collateralToLiquidate on bad debt (-2 for underestimation)"
        );
        assertEq(debtToRepay, maxRepay, "debtToRepay == maxRepay");

        token1.mint(liquidator, maxDebtToCover);
        vm.prank(liquidator);
        token1.approve(address(partialLiquidation), maxDebtToCover);

        emit log_named_decimal_uint("[test] maxDebtToCover", maxDebtToCover, 18);

        vm.prank(liquidator);
        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, maxDebtToCover, _receiveSToken);

        maxRepay = silo1.maxRepay(BORROWER);

        if (!_receiveSToken) {
            assertGt(maxRepay, 0, "there will be leftover");
        }

        token1.mint(liquidator, maxRepay);
        vm.prank(liquidator);
        token1.approve(address(partialLiquidation), maxRepay);

        (collateralToLiquidate, debtToRepay, sTokenRequired) = partialLiquidation.maxLiquidation(BORROWER);

        emit log_named_decimal_uint("[test] maxRepay", maxRepay, 18);

        assertEq(collateralToLiquidate, 0, "expect no collateral to liquidate");
        assertEq(debtToRepay, maxRepay, "expect debtToRepay to be equal to maxRepay");
        assertFalse(sTokenRequired, "expect sTokenRequired to be false, because not collateral");

        vm.expectRevert(IPartialLiquidation.NoCollateralToLiquidate.selector);
        vm.prank(liquidator);
        partialLiquidation.liquidationCall(address(token0), address(token1), BORROWER, maxRepay, _receiveSToken);

        assertEq(
            token1.balanceOf(address(silo1)),
            maxDebtToCover + 0.5e18,
            "[_liquidationCall_badDebt_full] silo has debt token == liquidation + original 0.5"
        );

        if (!_receiveSToken) {
            assertEq(
                token0.balanceOf(liquidator),
                // underestimation is 2, but this is bad debt, so we liquidated full collateral
                COLLATERAL,
                "[!_receiveSToken] expect to have liquidated collateral"
            );
        }

        assertEq(silo1.getDebtAssets(), maxRepay, "bad debt debt left");
        assertGt(silo1.getCollateralAssets(), 8e18, "collateral ready to borrow (with interests)");

        _liquidationModuleDoNotHaveTokens();
    }

    function _timeForwardAndDebug(uint256 _time) internal {
        emit log_named_uint("............................move forward days by", _time / 60 / 60 / 24);

        vm.warp(block.timestamp + _time);

        silo1.accrueInterest();
        silo0.accrueInterest();

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);

        (uint192 daoAndDeployerRevenue,,,,) = silo1.getSiloStorage();
        uint256 maxRepay = silo1.maxRepay(BORROWER);
        uint256 interest = maxRepay - DEBT - daoAndDeployerRevenue;
        uint256 liquidity = silo1.getLiquidity();

        emit log_named_decimal_uint("balance of silo1", token1.balanceOf(address(silo1)), 18);
        emit log_named_decimal_uint("silo1.getLiquidity()", liquidity, 18);

        emit log_named_decimal_uint("daoAndDeployerRevenue", daoAndDeployerRevenue, 18);
        emit log_named_decimal_uint("interest", interest, 18);
        emit log_named_decimal_uint("fee + interest", daoAndDeployerRevenue + interest, 18);

        int256 calculatedLiquidity =
            (COLLATERAL_FOR_BORROW - DEBT).toInt256() - uint256(daoAndDeployerRevenue).toInt256();

        emit log_named_decimal_int("(COLLATERAL_FOR_BORROW - DEBT) - fee == liquidity", calculatedLiquidity, 18);

        emit log_named_string(
            "calculatedLiquidity == liquidity", calculatedLiquidity == liquidity.toInt256() ? "YES" : "NO"
        );

        emit log_named_decimal_int(
            "liquidity without CAP == deposited + interest - DEBT - fee",
            (COLLATERAL_FOR_BORROW + interest).toInt256() - DEBT.toInt256()
                - uint256(daoAndDeployerRevenue).toInt256(),
            18
        );

        emit log_named_decimal_uint("borrower debt", maxRepay, 18);

        uint256 collateralBalanceOfUnderlying = SILO_LENS.collateralBalanceOfUnderlying(silo0, BORROWER);

        emit log_named_decimal_uint("borrower collateral", collateralBalanceOfUnderlying, 18);
        emit log_named_decimal_uint("collateralToLiquidate", collateralToLiquidate, 18);
        emit log_named_decimal_uint("debtToRepay", debtToRepay, 18);
        uint256 daysInDebt = (block.timestamp - debtStart) / 60 / 60 / 24;
        emit log_named_uint("days in debt", daysInDebt);
        emit log_named_decimal_uint("borrow APY %", (maxRepay - DEBT) * 1e18 / DEBT * 365 / daysInDebt, 16);
        emit log_named_decimal_uint("CAP %", 1e20, 16);

        emit log("-----");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxLiquidation_sTokenRequired_corrected_with_protected_assets
    */
    function test_maxLiquidation_sTokenRequired_corrected_with_protected_assets() public {
        _repay(DEBT, BORROWER);
        _withdraw(silo0.getLiquidity(), BORROWER);

        assertEq(silo0.getLiquidity(), 0, "Silo should have zero liquidity");

        address protectedBorrower = makeAddr("protectedBorrower");

        _makeDeposit(silo0, token0, COLLATERAL, protectedBorrower, ISilo.CollateralType.Protected);
        _borrow(DEBT, protectedBorrower);

        // Verify shares state
        address protectedShareToken = siloConfig.getConfig(address(silo0)).protectedShareToken;
        assertGt(IERC20(protectedShareToken).balanceOf(protectedBorrower), 0, "Borrower should have protected shares");
        assertEq(silo0.balanceOf(protectedBorrower), 0, "Borrower should have no collateral shares");

        // Move time forward to make borrower insolvent
        vm.warp(block.timestamp + 30 days);

        // Accrue interest
        silo0.accrueInterest();
        silo1.accrueInterest();

        assertFalse(silo0.isSolvent(protectedBorrower), "Borrower should be insolvent");

        // Get max liquidation from hook (original implementation with bug)
        (uint256 collateralToLiquidateHook, uint256 debtToRepayHook, bool sTokenRequiredHook) =
            partialLiquidation.maxLiquidation(protectedBorrower);

        // Get max liquidation from SiloLens (corrected implementation)
        // We can pass either silo0 or silo1
        (uint256 collateralToLiquidateLens, uint256 debtToRepayLens, bool sTokenRequiredLens,) =
            SILO_LENS.maxLiquidation(silo1, partialLiquidation, protectedBorrower);

        // Verify the bug: Hook says sTokenRequired=true because liquidity is 0
        assertTrue(sTokenRequiredHook, "Hook should incorrectly report sTokenRequired=true due to zero liquidity");

        // Verify the fix: SiloLens correctly considers protected assets
        assertFalse(
            sTokenRequiredLens,
            "SiloLens should correctly report sTokenRequired=false because protected assets are available"
        );

        // Verify amounts are the same
        assertEq(collateralToLiquidateHook, collateralToLiquidateLens, "Collateral amounts should match");
        assertEq(debtToRepayHook, debtToRepayLens, "Debt amounts should match");
    }

    function _liquidationModuleDoNotHaveTokens() private view {
        address module = address(partialLiquidation);

        assertEq(token0.balanceOf(module), 0);
        assertEq(token1.balanceOf(module), 0);

        assertEq(IShareToken(silo0Config.collateralShareToken).balanceOf(module), 0);
        assertEq(IShareToken(silo0Config.protectedShareToken).balanceOf(module), 0);
        assertEq(IShareToken(silo0Config.debtShareToken).balanceOf(module), 0);

        assertEq(IShareToken(silo1Config.collateralShareToken).balanceOf(module), 0);
        assertEq(IShareToken(silo1Config.protectedShareToken).balanceOf(module), 0);
        assertEq(IShareToken(silo1Config.debtShareToken).balanceOf(module), 0);
    }
}
