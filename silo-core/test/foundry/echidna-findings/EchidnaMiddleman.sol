// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {PartialLiquidationLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationLib.sol";

import {EchidnaSetup} from "./EchidnaSetup.sol";
import {MintableToken} from "../_common/MintableToken.sol";

contract EchidnaMiddleman is EchidnaSetup {
    using SafeCast for uint256;
    using SiloLensLib for ISilo;

    function __depositNeverMintsZeroShares(uint8 _actor, bool _siloZero, uint256 _amount) internal {
        emit log_named_string("    function", "__depositNeverMintsZeroShares");

        address actor = _chooseActor(_actor);
        ISilo silo = __chooseSilo(_siloZero);

        vm.prank(actor);
        silo.deposit(_amount, actor);
    }

    function __borrow(uint8 _actor, bool _siloZero, uint256 _amount) internal {
        emit log_named_string("    function", "__borrow");

        address actor = _chooseActor(_actor);
        ISilo silo = __chooseSilo(_siloZero);

        vm.prank(actor);
        silo.borrow(_amount, actor, actor);
    }

    function __previewDeposit_doesNotReturnMoreThanDeposit(uint8 _actor, uint256 _assets)
        internal
        returns (uint256 shares)
    {
        emit log_named_string("    function", "__previewDeposit_doesNotReturnMoreThanDeposit");

        address actor = _chooseActor(_actor);
        vm.startPrank(actor);

        uint256 depositShares = silo0.previewDeposit(_assets);
        shares = silo0.deposit(_assets, actor);
        assertEq(depositShares, shares, "previewDeposit fail");

        vm.stopPrank();
    }

    function __previewMint_DoesNotReturnLessThanMint(uint8 actorIndex, uint256 shares) public {
        emit log_named_string("    function", "__previewMint_DoesNotReturnLessThanMint");

        address actor = _chooseActor(actorIndex);
        uint256 previewAssets = silo0.previewMint(shares);

        vm.prank(actor);
        uint256 assets = silo0.mint(shares, actor);
        assertGe(previewAssets, assets, "previewMint underestimates assets!");
    }

    function __maxBorrow_correctReturnValue(uint8 _actor) internal returns (uint256 maxAssets, uint256 shares) {
        emit log_named_string("    function", "__maxBorrow_correctReturnValue");

        address actor = _chooseActor(_actor);
        maxAssets = silo0.maxBorrow(actor);

        vm.prank(actor);
        shares = silo0.borrow(maxAssets, actor, actor); // should not revert!
    }

    function __mint(uint8 _actor, bool _siloZero, uint256 _shares) internal {
        emit log_named_string("    function", "__mint");

        address actor = _chooseActor(_actor);
        ISilo silo = __chooseSilo(_siloZero);

        vm.prank(actor);
        silo.mint(_shares, actor);
    }

    function __maxBorrowShares_correctReturnValue(uint8 _actor)
        internal
        returns (uint256 maxBorrow, uint256 shares)
    {
        emit log_named_string("    function", "__maxBorrowShares_correctReturnValue");

        address actor = _chooseActor(_actor);

        maxBorrow = silo0.maxBorrowShares(actor);
        assertGt(maxBorrow, 0, "in echidna scenarios we exclude zeros, so we should not get it here as well");

        vm.prank(actor);
        shares = silo0.borrowShares(maxBorrow, actor, actor);
    }

    function __repayNeverReturnsZeroAssets(uint8 actorIndex, bool vaultZero, uint256 shares) public {
        emit log_named_string("    function", "__repayNeverReturnsZeroAssets");

        address actor = _chooseActor(actorIndex);

        vm.prank(actor);
        uint256 assets = (vaultZero ? silo0 : silo1).repayShares(shares, actor);
        assertGt(assets, 0, "repayShares returned zero assets");
    }

    function __maxLiquidation_correctReturnValue(uint8 _actor) internal {
        emit log_named_string("    function", "__maxLiquidation_correctReturnValue");

        address actor = _chooseActor(_actor);

        (bool isSolvent, ISilo siloWithDebt,) = _invariant_insolventHasDebt(actor);
        assertFalse(isSolvent, "expect not solvent user");

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(actor);

        (address collateral, address debt) = __liquidationTokens(address(siloWithDebt));

        __prepareForLiquidationRepay(siloWithDebt, actor, debtToRepay);

        vm.prank(actor);
        partialLiquidation.liquidationCall(debt, collateral, actor, debtToRepay, false);
    }

    function __maxWithdraw_correctMax(uint8 _actor) internal {
        emit log_named_string("    function", "__maxWithdraw_correctMax");

        address actor = _chooseActor(_actor);

        (, ISilo _siloWithCollateral) = _invariant_onlySolventUserCanRedeem(actor);
        _requireHealthySilo(_siloWithCollateral);

        uint256 maxAssets = _siloWithCollateral.maxWithdraw(actor);
        emit log_named_decimal_uint("maxWithdraw", maxAssets, 18);

        if (maxAssets == 0) {
            (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
                siloConfig.getConfigsForSolvency(actor);

            uint256 shareBalance = IERC20(collateralConfig.collateralShareToken).balanceOf(address(actor));
            uint256 debtShareBalance = IERC20(debtConfig.debtShareToken).balanceOf(address(actor));
            uint256 vaultLiquidity = _siloWithCollateral.getLiquidity();
            uint256 ltv = _siloWithCollateral.getLtv(address(actor));
            bool isSolvent = _siloWithCollateral.isSolvent(address(actor));

            // below are all cases where maxAssets can be 0
            if (shareBalance == 0 || !isSolvent || vaultLiquidity == 0) {
                // we good
            } else {
                emit log("[maxWithdraw_correctMax] maxAssets is zero for no reason");
                emit log(isSolvent ? "actor solvent" : "actor not solvent");
                emit log_named_uint("shareBalance", shareBalance);
                emit log_named_uint("debtShareBalance", debtShareBalance);
                emit log_named_uint("vault.getLiquidity()", vaultLiquidity);
                emit log_named_uint("ltv (is it close to LT?)", ltv);

                assertTrue(false, "why max withdraw is 0?");
            }
        }

        vm.prank(actor);
        _siloWithCollateral.withdraw(maxAssets, actor, actor);
    }

    function __deposit(uint8 _actor, bool _siloZero, uint256 _amount) internal {
        emit log_named_string("    function", "__deposit");

        address actor = _chooseActor(_actor);
        ISilo silo = __chooseSilo(_siloZero);

        vm.prank(actor);
        silo.deposit(_amount, actor);
    }

    function __transitionCollateral_doesNotResultInMoreShares(
        uint8 _actor,
        bool _siloZero,
        uint256 _amount,
        uint8 _type
    ) internal returns (uint256 transitionedAssets) {
        emit log_named_string("    function", "__transitionCollateral_doesNotResultInMoreShares");

        address actor = _chooseActor(_actor);

        ISilo vault = __chooseSilo(_siloZero);
        _invariant_checkForInterest(vault);

        (address protected, address collateral,) = siloConfig.getShareTokens(address(vault));

        uint256 maxWithdrawSumBefore;

        uint256 protBalanceBefore = IShareToken(protected).balanceOf(address(actor));
        uint256 collBalanceBefore = IShareToken(collateral).balanceOf(address(actor));

        {
            // too deep
            uint256 maxCollateralBefore = vault.maxWithdraw(address(actor), ISilo.CollateralType.Collateral);
            uint256 maxProtectedBefore = vault.maxWithdraw(address(actor), ISilo.CollateralType.Protected);
            maxWithdrawSumBefore = maxCollateralBefore + maxProtectedBefore;

            emit log("just before transitionCollateral (max should be with interest):");
            emit log_named_uint("maxRedeem maxCollateralBefore", maxCollateralBefore);
            emit log_named_uint("maxRedeem  maxProtectedBefore", maxProtectedBefore);
            emit log_named_uint("maxRedeem                     sum", maxWithdrawSumBefore);
        }

        vm.prank(actor);
        transitionedAssets = vault.transitionCollateral(_amount, actor, ISilo.CollateralType(_type));

        uint256 protBalanceAfter = IShareToken(protected).balanceOf(address(actor));
        uint256 collBalanceAfter = IShareToken(collateral).balanceOf(address(actor));

        {
            // too deep
            uint256 maxCollateralAfter = vault.maxWithdraw(address(actor), ISilo.CollateralType.Collateral);
            uint256 maxProtectedAfter = vault.maxWithdraw(address(actor), ISilo.CollateralType.Protected);
            uint256 maxAssetsSumAfter = maxCollateralAfter + maxProtectedAfter;

            emit log_named_uint("after transitionCollateral assets", transitionedAssets);
            emit log_named_uint("maxRedeem maxCollateralAfter", maxCollateralAfter);
            emit log_named_uint("maxRedeem  maxProtectedAfter", maxProtectedAfter);
            emit log_named_uint("maxRedeem                    sum", maxAssetsSumAfter);
            emit log_named_int("assets diff", maxWithdrawSumBefore.toInt256() - maxAssetsSumAfter.toInt256());

            assertGe(
                maxWithdrawSumBefore,
                maxAssetsSumAfter,
                "price is flat, so there should be no gains (we accept 1 wei diff)"
            );

            assertLe(maxWithdrawSumBefore - maxAssetsSumAfter, 1, "we accept 1 wei diff");
        }

        {
            // too deep
            // note: this could result in false positives due to interest calculation, and differences between
            // protected and unprotected shares/balances. Another way to check this property would be to
            // transitionCollateral in one direction, and then in the opposite direction, and only check shares/assets
            // after the second transition.

            emit log("transition back");

            (uint256 sharesTransitioned, ISilo.CollateralType _withdrawType) = _type
                == uint8(ISilo.CollateralType.Collateral)
                ? (protBalanceAfter - protBalanceBefore, ISilo.CollateralType.Protected)
                : (collBalanceAfter - collBalanceBefore, ISilo.CollateralType.Collateral);

            emit log_named_uint("sharesTransitioned", sharesTransitioned);

            vm.prank(actor);
            transitionedAssets = vault.transitionCollateral(sharesTransitioned, actor, _withdrawType);

            {
                uint256 maxCollateralBack = vault.maxWithdraw(address(actor), ISilo.CollateralType.Collateral);
                uint256 maxProtectedBack = vault.maxWithdraw(address(actor), ISilo.CollateralType.Protected);
                uint256 maxAssetsSumBack = maxCollateralBack + maxProtectedBack;

                emit log_named_uint("after back transitionCollateral", transitionedAssets);
                emit log_named_uint("maxWithdraw previewCollateralBack", maxCollateralBack);
                emit log_named_uint("maxWithdraw  previewProtectedBack", maxProtectedBack);
                emit log_named_uint("maxWithdraw                   sum", maxAssetsSumBack);
                emit log_named_int("assets diff", maxWithdrawSumBefore.toInt256() - maxAssetsSumBack.toInt256());

                assertGe(
                    maxWithdrawSumBefore,
                    maxAssetsSumBack,
                    "price is flat, so there should be no gains (we accept 1 wei diff)"
                );

                assertLe(maxWithdrawSumBefore - maxAssetsSumBack, 1, "we accept 1 wei diff");
            }

            protBalanceAfter = IShareToken(protected).balanceOf(address(actor));
            collBalanceAfter = IShareToken(collateral).balanceOf(address(actor));

            emit log_named_int("collateral shares diff", collBalanceBefore.toInt256() - collBalanceAfter.toInt256());
            emit log_named_int("protected shares diff", protBalanceBefore.toInt256() - protBalanceAfter.toInt256());

            assertLe(
                protBalanceBefore - protBalanceAfter,
                25,
                "[protected] there should be no gain in shares, accepting 25 wei loss because of rounding policy"
            );

            assertLe(
                collBalanceBefore - collBalanceAfter,
                25,
                "[collateral] there should be no gain in shares, accepting 25 wei loss because of rounding policy"
            );
        }
    }

    function __cannotPreventInsolventUserFromBeingLiquidated(uint8 _actor, bool _receiveShares) internal {
        emit log_named_string("    function", "__cannotPreventInsolventUserFromBeingLiquidated");

        address actor = _chooseActor(_actor);

        (bool isSolvent, ISilo siloWithDebt,) = _invariant_insolventHasDebt(actor);
        assertFalse(isSolvent, "expect not solvent user");

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(actor);
        (address collateral, address debt) = __liquidationTokens(address(siloWithDebt));

        __prepareForLiquidationRepay(siloWithDebt, actor, debtToRepay);

        vm.prank(actor);
        partialLiquidation.liquidationCall(debt, collateral, actor, debtToRepay, _receiveShares);
    }

    function __debtSharesNeverLargerThanDebt() internal {
        emit log_named_string("    function", "__debtSharesNeverLargerThanDebt");

        uint256 debt0 = silo0.getDebtAssets();
        uint256 debt1 = silo1.getDebtAssets();

        (,, address debtShareToken0) = siloConfig.getShareTokens(address(silo0));
        (,, address debtShareToken1) = siloConfig.getShareTokens(address(silo1));

        uint256 debtShareBalance0 = IShareToken(debtShareToken0).totalSupply();
        uint256 debtShareBalance1 = IShareToken(debtShareToken1).totalSupply();

        assertGe(debt0, debtShareBalance0, "[debt] assets0 must be >= shares0");
        assertGe(debt1, debtShareBalance1, "[debt] assets1 must be >= shares1");
    }

    function __borrowShares(uint8 _actorIndex, bool _siloZero, uint256 _shares) internal {
        emit log_named_string("    function", "__borrowShares");

        address actor = _chooseActor(_actorIndex);
        ISilo silo = __chooseSilo(_siloZero);

        vm.prank(actor);
        silo.borrowShares(_shares, actor, actor);
    }

    function __maxRedeem_correctMax(uint8 _actorIndex) internal {
        emit log_named_string("    function", "__maxRedeem_correctMax");

        address actor = _chooseActor(_actorIndex);

        (, ISilo _siloWithCollateral) = _invariant_onlySolventUserCanRedeem(actor);
        _requireHealthySilos();

        // you can redeem where there is no debt
        uint256 maxShares = _siloWithCollateral.maxRedeem(address(actor));
        assertGt(maxShares, 0, "Zero shares to withdraw");

        emit log_named_decimal_uint("Max Shares to redeem", maxShares, 18);

        vm.prank(actor);
        _siloWithCollateral.redeem(maxShares, actor, actor); // expect not to fail!
    }

    function __mintAssetType(uint8 _actorIndex, bool _vaultZero, uint256 _shares, uint8 _collateralType)
        public
        returns (uint256 assets)
    {
        emit log_named_string("    function", "__mintAssetType");

        address actor = _chooseActor(_actorIndex);
        ISilo silo = __chooseSilo(_vaultZero);

        vm.prank(actor);
        assets = silo.mint(_shares, actor, ISilo.CollateralType(_collateralType));

        assertLe(_collateralType, 3, "we have only 3 types");
    }

    function __withdraw(uint8 _actorIndex, bool _vaultZero, uint256 _assets) public {
        emit log_named_string("    function", "__withdraw");

        address actor = _chooseActor(_actorIndex);
        ISilo silo = __chooseSilo(_vaultZero);

        vm.prank(actor);
        silo.withdraw(_assets, actor, actor);
    }

    function __maxMint_correctMax(uint8 _actorIndex, bool _vaultZero) public {
        emit log_named_string("    function", "__maxMint_correctMax");

        address actor = _chooseActor(_actorIndex);
        ISilo silo = __chooseSilo(_vaultZero);

        uint256 maxShares = silo.maxMint(address(actor));
        assertGt(maxShares, 0, "max mint is zero");

        uint256 assets = silo.previewMint(maxShares);
        assertGt(assets, 0, "expect assets not to be 0");

        emit log_named_decimal_uint("Max Shares to mint:", maxShares, 18);

        vm.prank(actor);
        assertEq(silo.mint(maxShares, actor), assets, "expect preview to be correct");
    }

    function __accrueInterest(bool _vaultZero) public {
        emit log_named_string("    function", "__accrueInterest");

        ISilo silo = __chooseSilo(_vaultZero);
        silo.accrueInterest();
    }

    function __depositAssetType(uint8 _actorIndex, bool _vaultZero, uint256 _amount, uint8 _collateralType)
        public
        returns (uint256 shares)
    {
        emit log_named_string("    function", "__depositAssetType");

        address actor = _chooseActor(_actorIndex);
        ISilo silo = __chooseSilo(_vaultZero);

        vm.prank(actor);
        shares = silo.deposit(_amount, actor, ISilo.CollateralType(_collateralType));

        assertLe(_collateralType, 3, "we have only 3 types");
    }

    function __cannotLiquidateASolventUser(uint8 _actorIndex, bool _receiveShares) public {
        emit log_named_string("    function", "__cannotLiquidateASolventUser");

        address actor = _chooseActor(_actorIndex);
        (bool isSolvent, ISilo siloWithDebt,) = _invariant_insolventHasDebt(actor);

        assertFalse(isSolvent, "expect user to be solvent, not solvent should be ignored by echidna");

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(address(actor));
        (address collateral, address debt) = __liquidationTokens(address(siloWithDebt));

        try partialLiquidation.liquidationCall(debt, collateral, actor, debtToRepay, _receiveShares) {
            emit log("Solvent user liquidated!");
            assertTrue(false, "Solvent user liquidated!");
        } catch {
            // do nothing
        }
    }

    function __cannotFullyLiquidateSmallLtv(uint8 _actorIndex) public {
        emit log_named_string("    function", "__cannotFullyLiquidateSmallLtv");

        address actor = _chooseActor(_actorIndex);
        (bool isSolvent, ISilo siloWithDebt, ISilo siloWithCollateral) = _invariant_insolventHasDebt(actor);

        assertFalse(isSolvent, "expect not solvent user");

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(address(actor));
        assertFalse(isSolvent, "expect user to be not insolvent");

        uint256 ltvBefore = siloWithCollateral.getLtv(address(actor));
        uint256 lt = siloWithCollateral.getLt();

        emit log_named_decimal_uint("User LTV:", ltvBefore, 16);
        emit log_named_decimal_uint("Liq Threshold:", lt, 16);

        uint256 maxRepay = siloWithDebt.maxRepay(address(actor));
        // we assume we do not have oracle and price is 1:1
        uint256 maxPartialRepayValue = maxRepay * PartialLiquidationLib._FULL_LIQUIDATION_THRESHOLD / 1e18;

        (address collateral, address debt) = __liquidationTokens(address(siloWithDebt));
        partialLiquidation.liquidationCall(debt, collateral, actor, debtToRepay, false);

        uint256 ltvAfter = siloWithDebt.getLtv(address(actor));
        emit log_named_decimal_uint("afterLtv:", ltvAfter, 16);

        assertEq(silo0.getLtv(address(actor)), silo1.getLtv(address(actor)), "LTV must match on both silos");

        assertTrue(siloWithDebt.isSolvent(address(actor)), "expect user to be solvent (isSolvent)");

        if (debtToRepay < maxPartialRepayValue) {
            // if (partial)
            assertLt(ltvAfter, ltvBefore, "we expect LTV to go down after partial liquidation");
            assertGt(ltvAfter, 0, "ltvAfter > 0");
            assertLt(ltvAfter, lt, "ltvAfter < LT");
        } else {
            assertEq(ltvAfter, 0, "when not partial, user should be completely liquidated");
        }
    }

    function __cannotLiquidateUserUnderLt(uint8 _actorIndex, bool _receiveShares) public {
        emit log_named_string("    function", "__cannotLiquidateUserUnderLt");

        address actor = _chooseActor(_actorIndex);
        (bool isSolvent, ISilo siloWithDebt,) = _invariant_insolventHasDebt(actor);

        assertTrue(isSolvent, "expect not solvent user");

        uint256 lt = siloWithDebt.getLt();
        uint256 ltv = siloWithDebt.getLtv(address(actor));

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(address(actor));

        (address collateral, address debt) = __liquidationTokens(address(siloWithDebt));

        try partialLiquidation.liquidationCall(debt, collateral, actor, debtToRepay, _receiveShares) {
            emit log_named_decimal_uint("User LTV:", ltv, 16);
            emit log_named_decimal_uint("Liq Threshold:", lt, 16);
            emit log("User liquidated!");
            assert(false);
        } catch {
            assertLe(ltv, lt, "ltv <= lt");

            emit log_named_string(
                "it is expected liquidationCall to throw, because user is solvent", isSolvent ? "YES" : "NO?!"
            );
        }
    }

    function __chooseSilo(bool _siloZero) private view returns (ISilo) {
        return _siloZero ? silo0 : silo1;
    }

    function __liquidationTokens(address _siloWithDebt) private view returns (address collateral, address debt) {
        (collateral, debt) = _siloWithDebt == address(silo0)
            ? (address(token0), address(token1))
            : (address(token1), address(token0));
    }

    function __timeDelay(uint256 _t) internal {
        vm.warp(block.timestamp + _t);
    }

    function __timeDelay(uint256 _t, uint256 _roll) internal {
        vm.warp(block.timestamp + _t);
        vm.roll(block.number + _roll);
    }

    function __prepareForLiquidationRepay(ISilo _silo, address _actor, uint256 _debtToRepay) public {
        MintableToken token = _silo == silo0 ? token0 : token1;
        token.mintOnDemand(_actor, _debtToRepay);
        vm.prank(_actor);
        token.approve(address(_silo), _debtToRepay);
    }
}
