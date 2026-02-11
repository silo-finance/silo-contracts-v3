// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {DefaultingLiquidationCommon} from "./DefaultingLiquidationCommon.sol";

/*
tests for one way markets, borrowable token is 1
*/
contract DefaultingLiquidationBorrowable1Test is DefaultingLiquidationCommon {
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
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_happyPath_oneBorrower -vv --mc DefaultingLiquidationBorrowable1Test
    */
    function test_defaulting_happyPath_oneBorrower() public override {
        _check_defaulting_happyPath_oneBorrower(false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_happyPath_twoBorrowers -vv --mc DefaultingLiquidationBorrowable1Test
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

        assertGt(
            silo0.getLtv(borrower),
            0,
            "config for this market is less strict, lt ~75%, so we expect here partial liquidation"
        );

        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        UserState memory borrowerCollateralAfter = _getUserState(collateralSilo, borrower);
        UserState memory borrowerDebtAfter = _getUserState(debtSilo, borrower);

        {
            // silo check

            SiloState memory collateralSiloAfter = _getSiloState(collateralSilo);
            SiloState memory debtSiloAfter = _getSiloState(debtSilo);

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
                "[debtSilo] total collateral assets deducted"
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

            uint256 debtShares = borrowerDebtBefore.debtShares - borrowerDebtAfter.debtShares;

            assertEq(
                debtSiloBefore.totalDebtShares,
                debtSiloAfter.totalDebtShares + debtShares,
                "[debtSilo] total debt shares canceled by liquidated user debt"
            );
        }

        {
            // borrower checks

            uint256 collateralLiquidated = 0.090180018543589209e18; // hardcoded based on liquidation
            // if (_withOtherBorrower) collateralLiquidated -= 1;

            uint256 protectedLiquidated = collateralToLiquidate - collateralLiquidated;

            assertEq(
                borrowerCollateralBefore.collateralAssets,
                borrowerCollateralAfter.collateralAssets + collateralLiquidated,
                "[collateralUser] borrower collateral taken"
            );

            assertEq(
                borrowerCollateralBefore.protectedAssets,
                borrowerCollateralAfter.protectedAssets + protectedLiquidated,
                "[collateralUser] borrower protected taken"
            );

            // with two borrowers 1 wei was transfered to the one that is doing repay
            // because we alwasy repay "more"
            assertEq(
                borrowerDebtBefore.debtAssets - debtToRepay, // + (_withOtherBorrower ? 1 : 0),
                borrowerDebtAfter.debtAssets,
                "[debtUser] borrower debt canceled"
            );
        }

        {
            // lpProvider checks

            uint256 totalGaugeRewards = 0.089321161224126454629e21; // hardcoded based on logs
            // if (_withOtherBorrower) totalGaugeRewards -= 990;

            uint256 totalProtectedRewards = 0.495238095238095238096e21; // hardcoded based on logs
            (address protectedShareToken,,) = siloConfig.getShareTokens(address(collateralSilo));

            assertEq(collateralSilo.balanceOf(address(gauge)), totalGaugeRewards, "gauge shares/rewards");

            assertEq(
                IShareToken(protectedShareToken).balanceOf(address(gauge)),
                totalProtectedRewards,
                "protected shares/rewards"
            );

            address lpProvider = makeAddr("lpProvider");

            {
                uint256 lpProviderCollateralLeft = 0.520865162326427786e18; // hardcoded based on logs
                if (_withOtherBorrower) lpProviderCollateralLeft += 1.082941370463179415e18;

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

            uint256 daoBalance = IERC20(debtSilo.asset()).balanceOf(daoFeeReceiver);
            uint256 deployerBalance = IERC20(debtSilo.asset()).balanceOf(deployerFeeReceiver);
            assertEq(daoBalance + deployerBalance, revenue, "dao and deployer should receive whole revenue");
        }

        {
            //exit from debt silo
            _assertUserCanExit(debtSilo, makeAddr("protectedUser"));

            // this case is partial liquidation, so we need to repay the debt to exit
            token1.setOnDemand(true);
            debtSilo.repayShares(borrowerDebtAfter.debtShares, borrower);

            if (_withOtherBorrower) {
                debtSilo.repayShares(debtSilo.maxRepayShares(makeAddr("otherBorrower")), makeAddr("otherBorrower"));
            }

            token1.setOnDemand(false);

            _assertUserCanExit(debtSilo, makeAddr("lpProvider"));
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_gaugeManagement_noWarp -vv --mc DefaultingLiquidationBorrowable1Test
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

        uint256 gauge2Rewards = borrowerCollateralShareToken.balanceOf(address(gauge2));
        assertEq(
            gauge2Rewards,
            582.5851509190352016e18,
            "gauge2 should have only collateral rewards from borrower2 liquidation"
        );
        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("keeper2")),
            5.6017802972984154e18,
            "keeper2 fee from borrower2 liquidation"
        );
        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper2")),
            0,
            "keeper2 fee from borrower2 liquidation (protected)"
        );

        uint256 gauge2CollateralRewards1 = gauge2.getRewardsBalance(makeAddr("lpProvider1"), programNames[0]);
        uint256 gauge2CollateralRewards2 = gauge2.getRewardsBalance(makeAddr("lpProvider2"), programNames[0]);

        assertEq(gauge2CollateralRewards1, 291.2925754595176008e18, "[lpProvider1] gauge2 has claimable rewards");
        assertEq(gauge2CollateralRewards2, 291.2925754595176008e18, "[lpProvider2] gauge2 has claimable rewards");

        assertEq(
            borrowerProtectedShareToken.balanceOf(address(gauge3)),
            58.520509988022695848e18,
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
            29.260254994011347924e18,
            "[lpProvider1] gauge3 collateral rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("lpProvider2")),
            29.260254994011347924e18,
            "[lpProvider2] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper3")),
            0.562697211423295152e18,
            "keeper3 fee from borrower3 liquidation (protected)"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_gaugeManagement_warp -vv --mc DefaultingLiquidationBorrowable1Test
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

        uint256 gauge2Rewards = borrowerCollateralShareToken.balanceOf(address(gauge2));
        assertEq(
            gauge2Rewards,
            582.590933947354604877e18,
            "gauge2 should have only collateral rewards from borrower2 liquidation"
        );
        assertEq(
            borrowerCollateralShareToken.balanceOf(makeAddr("keeper2")),
            5.601835903339948123e18,
            "keeper2 fee from borrower2 liquidation"
        );
        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper2")),
            0,
            "keeper2 fee from borrower2 liquidation (protected)"
        );

        uint256 gauge2CollateralRewards1 = gauge2.getRewardsBalance(makeAddr("lpProvider1"), programNames[0]);
        uint256 gauge2CollateralRewards2 = gauge2.getRewardsBalance(makeAddr("lpProvider2"), programNames[0]);

        assertEq(gauge2CollateralRewards1, 291.295466973677302438e18, "[lpProvider1] gauge2 has claimable rewards");
        assertEq(gauge2CollateralRewards2, 291.295466973677302438e18, "[lpProvider2] gauge2 has claimable rewards");

        assertEq(
            borrowerProtectedShareToken.balanceOf(address(gauge3)),
            58.521064387728034362e18,
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
            29.260532193864017181e18,
            "[lpProvider1] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("lpProvider2")),
            29.260532193864017181e18,
            "[lpProvider2] gauge3 protected rewards"
        );

        assertEq(
            borrowerProtectedShareToken.balanceOf(makeAddr("keeper3")),
            0.562702542189692638e18,
            "keeper3 fee from borrower3 liquidation (protected)"
        );
    }

    // CONFIGURATION

    function _getSilos() internal view override returns (ISilo collateralSilo, ISilo debtSilo) {
        collateralSilo = silo0;
        debtSilo = silo1;
    }

    function _getTokens() internal view override returns (address collateralAsset, address debtAsset) {
        collateralAsset = address(token0);
        debtAsset = address(token1);
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
        return SiloConfigsNames.SILO_LOCAL_NO_ORACLE_DEFAULTING0;
    }
}
