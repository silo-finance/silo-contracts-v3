// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {DefaultingLiquidationCommon} from "./DefaultingLiquidationCommon.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingLiquidationBorrowable0Test -vv
tests for one way markets, borrowable token is 0
*/
contract DefaultingLiquidationBorrowable0Test is DefaultingLiquidationCommon {
    using SiloLensLib for ISilo;

    function setUp() public override {
        super.setUp();

        (address collateralAsset, address debtAsset) = _getTokens();
        assertNotEq(
            collateralAsset,
            debtAsset,
            "[crosscheck] collateral and debt assets should be different for two assets case"
        );

        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();
        assertNotEq(address(collateralSilo), address(debtSilo), "[crosscheck] silos must be different for this case");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_happyPath -vv
    */
    function test_defaulting_happyPath_oneBorrower() public override {
        _check_defaulting_happyPath_oneBorrower(false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_happyPath_twoBorrowers -vv --mc DefaultingLiquidationBorrowable0Test
    */
    function test_defaulting_happyPath_twoBorrowers() public override {
        _check_defaulting_happyPath_oneBorrower(true);
    }

    function _check_defaulting_happyPath_oneBorrower(bool _withOtherBorrower) internal {
        (
            UserState memory borrowerCollateralBefore,
            UserState memory borrowerDebtBefore,
            SiloState memory collateralSiloBefore,
            SiloState memory debtSiloBefore,
            uint256 collateralToLiquidate,
            uint256 debtToRepay
        ) = _defaulting_happyPath(_withOtherBorrower);

        assertEq(silo0.getLtv(borrower), 0, "LT config for this market is 97%, so we expect here full liquidation");

        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        UserState memory borrowerCollateralAfter = _getUserState(collateralSilo, borrower);
        UserState memory borrowerDebtAfter = _getUserState(debtSilo, borrower);

        {
            // silo check

            SiloState memory collateralSiloAfter = _getSiloState(collateralSilo);
            SiloState memory debtSiloAfter = _getSiloState(debtSilo);

            uint256 debtShares = borrowerDebtBefore.debtShares - borrowerDebtAfter.debtShares;

            assertEq(
                collateralSiloBefore.totalCollateralShares,
                collateralSiloAfter.totalCollateralShares,
                "[collateralSilo] collateral total shares did not change, we distribute"
            );

            assertEq(
                collateralSiloBefore.totalProtectedShares,
                collateralSiloAfter.totalProtectedShares,
                "[collateralSilo] total protected shares did not change, we distribute"
            );

            assertEq(
                collateralSiloBefore.totalCollateral,
                collateralSiloAfter.totalCollateral,
                "[collateralSilo] collateral total assets did not changed, we distribute"
            );

            assertEq(
                collateralSiloBefore.totalProtected,
                collateralSiloAfter.totalProtected,
                "[collateralSilo] total protected assets did not changed, we distribute"
            );

            assertEq(
                collateralSiloBefore.totalDebt + collateralSiloAfter.totalDebt,
                0,
                "[collateralSilo] total debt on collateral side should not exist"
            );

            assertEq(
                collateralSiloBefore.totalDebtShares + collateralSiloAfter.totalDebtShares,
                0,
                "[collateralSilo] total debt shares on collateral side should not exist"
            );

            assertEq(
                debtSiloBefore.totalCollateralShares,
                debtSiloAfter.totalCollateralShares,
                "[debtSilo] collateral total shares did not change, value did change"
            );

            assertEq(
                debtSiloBefore.totalCollateral,
                debtSiloAfter.totalCollateral + debtToRepay,
                "[debtSilo] total collateralassets deducted"
            );

            assertEq(
                debtSiloBefore.totalProtectedShares,
                debtSiloAfter.totalProtectedShares,
                "[debtSilo] total protected shares must stay protected!"
            );

            assertEq(
                debtSiloBefore.totalProtected,
                debtSiloAfter.totalProtected,
                "[debtSilo] total protected assets must stay protected!"
            );

            assertEq(debtSiloBefore.totalProtected, 1e18, "[debtSilo] total protected assets exists");

            assertEq(
                debtSiloBefore.totalDebt, debtSiloAfter.totalDebt + debtToRepay, "[debtSilo] total debt was canceled"
            );

            assertEq(
                debtSiloAfter.totalDebt,
                debtSilo.maxRepay(makeAddr("otherBorrower")),
                "[debtSilo] total debt is 0 (or just other debt) now, because of full liquidation"
            );

            assertEq(
                debtSiloBefore.totalDebtShares,
                debtSiloAfter.totalDebtShares + debtShares,
                "[debtSilo] total debt shares canceled by liquidated user debt"
            );

            assertEq(
                debtSiloAfter.totalDebtShares,
                debtSilo.maxRepayShares(makeAddr("otherBorrower")),
                "[debtSilo] total debt shares is 0 (or only other debt shares) now, because of full liquidation"
            );
        }

        {
            // borrower checks

            uint256 collateralLiquidated = 0.5e18; // hardcoded based on liquidation

            uint256 protectedLiquidated = collateralToLiquidate - collateralLiquidated;

            assertEq(
                borrowerCollateralBefore.collateralAssets,
                collateralLiquidated,
                "[collateralUser] borrower collateral before liquidation"
            );

            assertEq(
                borrowerCollateralAfter.collateralAssets,
                0,
                "[collateralUser] borrower collateral was fully liquidated"
            );

            assertEq(
                borrowerCollateralBefore.protectedAssets,
                protectedLiquidated,
                "[collateralUser] borrower protected before liquidation"
            );

            assertEq(
                borrowerCollateralAfter.protectedAssets, 0, "[collateralUser] borrower protected was fully liquidated"
            );

            assertEq(borrowerDebtBefore.debtAssets, debtToRepay, "[debtUser] debt amount canceled");

            assertEq(borrowerDebtAfter.debtAssets, 0, "[debtUser] borrower debt canceled");
        }

        {
            // lpProvider checks

            uint256 totalGaugeRewards = 0.499512389292466912131e21; // hardcoded based on logs

            uint256 totalProtectedRewards = 0.499512389292466912131e21; // hardcoded based on logs

            (address protectedShareToken,,) = siloConfig.getShareTokens(address(collateralSilo));

            assertEq(collateralSilo.balanceOf(address(gauge)), totalGaugeRewards, "gauge shares/rewards");

            assertEq(
                IShareToken(protectedShareToken).balanceOf(address(gauge)),
                totalProtectedRewards,
                "gauge protected shares/rewards"
            );

            address lpProvider = makeAddr("lpProvider");

            {
                uint256 lpProviderCollateralLeft = 0.016553668919408922e18; // hardcoded based on logs
                if (_withOtherBorrower) lpProviderCollateralLeft += 1.012738993241773239e18;

                assertEq(
                    _getUserState(debtSilo, lpProvider).collateralAssets,
                    lpProviderCollateralLeft, // hardcoded based on logs
                    "[lpProvider] collateral cut by liquidated collateral"
                );
            }

            assertEq(
                collateralSilo.balanceOf(lpProvider), 0, "[lpProvider] shares are not in lp wallet, they are in gauge"
            );

            assertEq(
                IShareToken(protectedShareToken).balanceOf(lpProvider),
                0,
                "[lpProvider] protected shares are not in lp wallet, they are in gauge"
            );

            vm.prank(lpProvider);
            gauge.claimRewards(lpProvider);

            assertEq(collateralSilo.balanceOf(lpProvider), totalGaugeRewards, "[lpProvider] rewards claimed");

            assertEq(
                IShareToken(protectedShareToken).balanceOf(lpProvider),
                totalProtectedRewards,
                "[lpProvider] protected rewards claimed"
            );

            uint256 collateralAssets = collateralSilo.previewRedeem(totalGaugeRewards);
            uint256 protectedAssets =
                collateralSilo.previewRedeem(totalProtectedRewards, ISilo.CollateralType.Protected);
            uint256 lpAssets = debtSilo.previewRedeem(debtSilo.balanceOf(lpProvider));

            assertGt(
                collateralAssets + protectedAssets + lpAssets,
                1e18,
                "[lpProvider] because there was no bad debt and price is 1:1 we expect total assets as return + interest"
            );
        }

        {
            // protected user check
            assertEq(
                debtSilo.maxWithdraw(makeAddr("protectedUser"), ISilo.CollateralType.Protected),
                1e18,
                "protected user should be able to withdraw all"
            );
        }

        {
            // fees checks - expect whole amount to be transfered
            (uint256 revenue,) = _printRevenue(debtSilo);
            (address daoFeeReceiver, address deployerFeeReceiver) =
                debtSilo.factory().getFeeReceivers(address(debtSilo));

            _assertWithdrawableFees(debtSilo);
            _assertNoWithdrawableFees(debtSilo);

            _printRevenue(debtSilo);

            uint256 daoBalance = IERC20(debtSilo.asset()).balanceOf(daoFeeReceiver);
            uint256 deployerBalance = IERC20(debtSilo.asset()).balanceOf(deployerFeeReceiver);
            assertEq(daoBalance + deployerBalance, revenue, "dao and deployer should receive whole revenue");
        }

        {
            if (_withOtherBorrower) {
                token0.setOnDemand(true);
                debtSilo.repayShares(debtSilo.maxRepayShares(makeAddr("otherBorrower")), makeAddr("otherBorrower"));
                token0.setOnDemand(false);
            }

            //exit from debt silo
            _assertUserCanExit(debtSilo, makeAddr("protectedUser"));
            _assertUserCanExit(debtSilo, makeAddr("lpProvider"));
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_bothLiquidationsResultsMatch_insolvent_fuzz -vv --mc DefaultingLiquidationBorrowable0 --fuzz-runs 10
    */
    /// forge-config: core_test.fuzz.runs = 10
    function test_bothLiquidationsResultsMatch_insolvent_fuzz_limit(
        uint64 _dropPercentage,
        uint32 _warp,
        uint48 _collateral,
        uint48 _protected
    ) public override {
        _dropPercentage = 0.061e18;
        _warp = 5 days;

        super.test_bothLiquidationsResultsMatch_insolvent_fuzz_limit(_dropPercentage, _warp, _collateral, _protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_gaugeManagement_noWarp -vv --mc DefaultingLiquidationBorrowable0Test
    */
    function test_incentiveDistribution_gaugeManagement_noWarp() public override {
        (
            ISiloIncentivesController gauge2,
            ISiloIncentivesController gauge3,
            IShareToken borrowerCollateralShareToken,
            IShareToken borrowerProtectedShareToken
        ) = _incentiveDistribution_gaugeManagement({_warp: false});

        string[] memory programNames = new string[](2);
        programNames[0] = _getProgramNameForAddress(address(borrowerCollateralShareToken));
        programNames[1] = _getProgramNameForAddress(address(borrowerProtectedShareToken));

        assertEq(
            borrowerCollateralShareToken.balanceOf(address(gauge2)),
            999.024778584933824262e18,
            "gauge2 should have only collateral rewards from borrower2 liquidation"
        );
        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("keeper2")),
            0.975221415066175738e18,
            "keeper2 fee from borrower2 liquidation"
        );
        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper2")),
            0,
            "keeper2 fee from borrower2 liquidation (protected)"
        );

        uint256 gauge2CollateralRewards1 = gauge2.getRewardsBalance(makeAddr("lpProvider1"), programNames[0]);
        uint256 gauge2CollateralRewards2 = gauge2.getRewardsBalance(makeAddr("lpProvider2"), programNames[0]);

        assertEq(gauge2CollateralRewards1, 499.512389292466912131e18, "[lpProvider1] gauge2 has claimable rewards");
        assertEq(gauge2CollateralRewards2, 499.512389292466912131e18, "[lpProvider2] gauge2 has claimable rewards");

        assertEq(
            borrowerProtectedShareToken.balanceOf(address(gauge3)),
            99.902477858493382427e18,
            "gauge3 should have only protected rewards"
        );

        vm.startPrank(makeAddr("lpProvider1"));
        gauge2.claimRewards(makeAddr("lpProvider1"));
        gauge3.claimRewards(makeAddr("lpProvider1"));
        vm.stopPrank();

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider1")),
            gauge2CollateralRewards1,
            "[lpProvider1] gauge2 collateral rewards"
        );

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider1")),
            gauge2CollateralRewards1,
            "[lpProvider1] gauge3 collateral rewards"
        );

        vm.startPrank(makeAddr("lpProvider2"));
        gauge2.claimRewards(makeAddr("lpProvider2"));
        gauge3.claimRewards(makeAddr("lpProvider2"));
        vm.stopPrank();

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider1")),
            gauge2CollateralRewards2,
            "[lpProvider1] gauge2 collateral rewards, did not changed"
        );

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider2")),
            gauge2CollateralRewards2,
            "[lpProvider2] gauge2 collateral rewards, did not changed"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("lpProvider1")),
            49.951238929246691213e18,
            "[lpProvider1] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("lpProvider2")),
            49.951238929246691213e18,
            "[lpProvider2] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper3")),
            0.097522141506617573e18,
            "keeper3 fee from borrower3 liquidation (protected)"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_gaugeManagement_warp -vv --mc DefaultingLiquidationBorrowable0Test
    */
    function test_incentiveDistribution_gaugeManagement_warp() public override {
        // warp by 1h should increase rewards distribution a little bit
        (
            ISiloIncentivesController gauge2,
            ISiloIncentivesController gauge3,
            IShareToken borrowerCollateralShareToken,
            IShareToken borrowerProtectedShareToken
        ) = _incentiveDistribution_gaugeManagement({_warp: true});

        string[] memory programNames = new string[](2);
        programNames[0] = _getProgramNameForAddress(address(borrowerCollateralShareToken));
        programNames[1] = _getProgramNameForAddress(address(borrowerProtectedShareToken));

        assertEq(
            borrowerCollateralShareToken.balanceOf(address(gauge2)),
            999.024778584933824262e18,
            "gauge2 should have only collateral rewards from borrower2 liquidation"
        );
        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("keeper2")),
            0.975221415066175738e18,
            "keeper2 fee from borrower2 liquidation"
        );
        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper2")),
            0,
            "keeper2 fee from borrower2 liquidation (protected)"
        );

        uint256 gauge2CollateralRewards1 = gauge2.getRewardsBalance(makeAddr("lpProvider1"), programNames[0]);
        uint256 gauge2CollateralRewards2 = gauge2.getRewardsBalance(makeAddr("lpProvider2"), programNames[0]);

        assertEq(gauge2CollateralRewards1, 499.512389292466912131e18, "[lpProvider1] gauge2 has claimable rewards");
        assertEq(gauge2CollateralRewards2, 499.512389292466912131e18, "[lpProvider2] gauge2 has claimable rewards");

        assertEq(
            borrowerProtectedShareToken.balanceOf(address(gauge3)),
            99.902477858493382427e18,
            "gauge3 should have only protected rewards"
        );

        vm.startPrank(makeAddr("lpProvider1"));
        gauge2.claimRewards(makeAddr("lpProvider1"));
        gauge3.claimRewards(makeAddr("lpProvider1"));
        vm.stopPrank();

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider1")),
            gauge2CollateralRewards1,
            "[lpProvider1] gauge2 collateral rewards"
        );

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider1")),
            gauge2CollateralRewards1,
            "[lpProvider1] gauge2 collateral rewards"
        );

        vm.startPrank(makeAddr("lpProvider2"));
        gauge2.claimRewards(makeAddr("lpProvider2"));
        gauge3.claimRewards(makeAddr("lpProvider2"));
        vm.stopPrank();

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider1")),
            gauge2CollateralRewards2,
            "[lpProvider1] gauge2 collateral rewards, did not changed"
        );

        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("lpProvider2")),
            gauge2CollateralRewards2,
            "[lpProvider2] gauge2 collateral rewards, did not changed"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("lpProvider1")),
            49.951238929246691213e18,
            "[lpProvider1] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("lpProvider2")),
            49.951238929246691213e18,
            "[lpProvider2] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper3")),
            0.097522141506617573e18,
            "keeper3 fee from borrower3 liquidation (protected)"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_DefaultingLiquidationData -vv --mc DefaultingLiquidationBorrowable0Test
    */
    function test_defaulting_DefaultingLiquidationData() public {
        _addLiquidity(1e18);

        _createPosition({_borrower: borrower, _collateral: 1e18, _protected: 1e18, _maxOut: true});

        _setCollateralPrice(0.98e18);

        _moveUntillDefaultingPossible(borrower, 0.001e18, 1 days);

        _createIncentiveController();

        (,ISilo debtSilo) = _getSilos();

        // hardcoded based on logs
        uint256 withdrawAssetsFromCollateral = 1e18;
        uint256 withdrawAssetsFromProtected = 1e18;
        uint256 repayDebtAssets = 2.046343284218735174e18;

        vm.expectEmit(true, true, true, true);
        emit IPartialLiquidationByDefaulting.DefaultingLiquidationData({
            debtSilo: address(debtSilo),
            borrower: borrower,
            withdrawAssetsFromCollateral: withdrawAssetsFromCollateral,
            withdrawAssetsFromProtected: withdrawAssetsFromProtected,
            repayDebtAssets: repayDebtAssets
        });
            
        (uint256 collateralToLiquidate, uint256 debtToRepay) = defaulting.liquidationCallByDefaulting(borrower);

        assertEq(collateralToLiquidate, withdrawAssetsFromCollateral + withdrawAssetsFromProtected, "collateralToLiquidate match");
        assertEq(debtToRepay, repayDebtAssets, "debtToRepay match");
    }

    // CONFIGURATION

    function _getSilos() internal view override returns (ISilo collateralSilo, ISilo debtSilo) {
        collateralSilo = silo1;
        debtSilo = silo0;
    }

    function _getTokens() internal view override returns (address collateralAsset, address debtAsset) {
        collateralAsset = address(token1);
        debtAsset = address(token0);
    }

    function _executeBorrow(address _borrower, uint256 _amount) internal override returns (bool success) {
        (, ISilo debtSilo) = _getSilos();
        vm.prank(_borrower);

        try debtSilo.borrow(_amount, _borrower, _borrower) {
            success = true;
        } catch {
            success = false;
        }
    }

    function _useConfigName() internal pure override returns (string memory) {
        return SiloConfigsNames.SILO_LOCAL_NO_ORACLE_DEFAULTING1;
    }
}
