// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {DefaultingLiquidationHelpers} from "./DefaultingLiquidationHelpers.sol";

abstract contract DefaultingLiquidationAsserts is DefaultingLiquidationHelpers {
    /// @param _allowForDust if true, we assert that the user is dead, NO dust is allowed
    /// why? eg. if we have 4000 shares this give us 11 assets ot withdraw, but when we convert
    /// 11 assets back to shares, we will get eg 3929 (with rounding up), bacause of that dust will be left
    /// this case was observed so far in same assets positions.
    function _assertNoShareTokens(ISilo _silo, address _user, bool _allowForDust, string memory _msg) internal {
        console2.log("[_assertNoShareTokens] on silo %s for user %s", vm.getLabel(address(_silo)), vm.getLabel(_user));

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(_silo));

        uint256 balance = IShareToken(protectedShareToken).balanceOf(_user);

        if (_allowForDust) {
            _assertNoRedeemable(
                _silo,
                _user,
                ISilo.CollateralType.Protected,
                _allowForDust,
                string.concat("[_assertNoShareTokens] no protected dust: ", _msg)
            );
        } else {
            assertEq(balance, 0, string.concat("[_assertNoShareTokens] protected: ", _msg));
        }

        balance = IShareToken(collateralShareToken).balanceOf(_user);

        if (_silo.getTotalAssetsStorage(ISilo.AssetType.Collateral) != 0) {
            if (_allowForDust) {
                _assertNoRedeemable(
                    _silo,
                    _user,
                    ISilo.CollateralType.Collateral,
                    _allowForDust,
                    string.concat("[_assertNoShareTokens] no collateral dust: ", _msg)
                );
            } else {
                assertEq(balance, 0, string.concat("[_assertNoShareTokens] collateral: ", _msg));
            }
        } else {
            // the state of silo is undefined here,
            // it is possible to have shares but no assets after defaulting
        }

        balance = IShareToken(debtShareToken).balanceOf(_user);
        assertEq(balance, 0, string.concat("[_assertNoShareTokens] debt: ", _msg));
    }

    function _assertWithdrawableFees(ISilo _silo) internal {
        _silo.accrueInterest();

        _printFractions(_silo);

        (uint256 fees,,,,) = _silo.getSiloStorage();

        if (fees == 0) {
            // check fractions, they need to be >0
            ISilo.Fractions memory fractions = _silo.getFractionsStorage();
            assertGt(fractions.revenue, 0, "[_assertWithdrawableFees] expect revenue fractions to be greater than 0");
        } else {
            _silo.withdrawFees();
        }
    }

    function _assertNoRedeemable(
        ISilo _silo,
        address _user,
        ISilo.CollateralType _collateralType,
        bool _allowForDust,
        string memory _msg
    ) internal {
        try _silo.redeem(_silo.balanceOf(_user), _user, _user, _collateralType) returns (uint256 assets) {
            if (_allowForDust) {
                assertEq(
                    assets, 1, string.concat(_msg, " [_assertNoRedeemable] redeem should give us max 1 wei of assets")
                );
            } else {
                revert(
                    string.concat(
                        _msg, " [_assertNoRedeemable] redeem should fail, after defaulting we expect zero assets"
                    )
                );
            }
        } catch {
            // OK
        }
    }

    function _assertNoWithdrawableFees(ISilo _silo) internal {
        _silo.accrueInterest();

        vm.expectRevert(ISilo.EarnedZero.selector);
        _silo.withdrawFees();

        (uint256 fees,,,,) = _silo.getSiloStorage();
        assertEq(
            fees, 0, string.concat("[_assertNoWithdrawableFees] expect NO fees for ", vm.getLabel(address(_silo)))
        );

        // check fractions, they need to be 0 as well
        ISilo.Fractions memory fractions = _silo.getFractionsStorage();
        assertEq(fractions.interest, 0, "[_assertNoWithdrawableFees] expect NO interest fractions");
        assertEq(fractions.revenue, 0, "[_assertNoWithdrawableFees] expect NO revenue fractions");
    }

    function _assertEveryoneCanExitFromSilo(ISilo _silo, bool _allowForDust) internal {
        assertGt(depositors.length, 0, "[_assertEveryoneCanExit] no depositors to check");

        (,, address debtShareToken) = siloConfig.getShareTokens(address(_silo));

        assertEq(
            IShareToken(debtShareToken).totalSupply(),
            0,
            "[_assertEveryoneCanExit] debt must be 0 in order exit to work"
        );

        for (uint256 i; i < depositors.length; i++) {
            _assertUserCanExit(_silo, depositors[i]);
        }

        // we need another loop for a case, when dust left and only one user present, so he can exit with dust
        for (uint256 i; i < depositors.length; i++) {
            _assertUserCanExit(_silo, depositors[i]);
        }

        // separate loop is needed after everyone exit, because noShareTokens depends on final total assets
        for (uint256 i; i < depositors.length; i++) {
            _assertNoShareTokens(_silo, depositors[i], _allowForDust, "_assertEveryoneCanExitFromSilo");
        }
    }

    function _assertTotalSharesZeroOnlyGauge(ISilo _silo) internal view {
        uint256 totalAssetsLeft = _silo.getTotalAssetsStorage(ISilo.AssetType.Collateral);

        (address protectedShareToken,,) = siloConfig.getShareTokens(address(_silo));

        if (totalAssetsLeft == 0) {
            // when no assets, even when we have shares state is unknown
        } else if (totalAssetsLeft == 1) {
            console2.log("totalAssetsLeft == 1, accepting as dust");
            // we accept this as dust, rounding error
        } else {
            uint256 gaugeCollateral = _silo.balanceOf(address(gauge));
            console2.log("gaugeCollateral", gaugeCollateral);

            assertEq(
                _silo.totalSupply(),
                gaugeCollateral,
                "[_assertTotalSharesZeroOnlyGauge] silo should have only gauge collateral"
            );
        }

        uint256 gaugeProtected = IShareToken(protectedShareToken).balanceOf(address(gauge));

        console2.log("gaugeProtected", gaugeProtected);

        assertEq(
            IShareToken(protectedShareToken).totalSupply(),
            gaugeProtected,
            "[_assertTotalSharesZeroOnlyGauge] protected share token should have only gauge protected"
        );
    }

    function _assertTotalSharesZero(ISilo _silo) internal view {
        uint256 totalAssetsLeft = _silo.getTotalAssetsStorage(ISilo.AssetType.Collateral);

        (address protectedShareToken,,) = siloConfig.getShareTokens(address(_silo));

        console2.log("gaugeCollateral", _silo.balanceOf(address(gauge)));
        console2.log("gaugeProtected", IShareToken(protectedShareToken).balanceOf(address(gauge)));

        if (totalAssetsLeft == 0) {
            // when no assets, even when we have shares state is unknown
        } else if (totalAssetsLeft == 1) {
            console2.log("totalAssetsLeft == 1, accepting as dust");
            // we accept this as dust, rounding error
        } else {
            assertEq(_silo.totalSupply(), 0, "[_assertTotalSharesZero] silo should have NO collateral");
        }

        assertEq(
            IShareToken(protectedShareToken).totalSupply(),
            0,
            "[_assertTotalSharesZero] silo should have NO protected shares"
        );
    }

    function _assertUserCanExit(ISilo _silo, address _user) internal {
        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(_silo));

        vm.startPrank(_user);
        uint256 balance = IShareToken(collateralShareToken).balanceOf(_user);
        uint256 redeemable = _silo.maxRedeem(_user);

        emit log_named_decimal_uint(
            string.concat("[", vm.getLabel(collateralShareToken), "] ", vm.getLabel(_user), " collateral shares"),
            balance,
            21
        );
        emit log_named_decimal_uint("\tredeemable", redeemable, 21);
        // using balance instead of redeemable to clear out as much shares as we can
        if (redeemable != 0) _silo.redeem(balance, _user, _user);

        balance = IShareToken(protectedShareToken).balanceOf(_user);
        redeemable = _silo.maxRedeem(_user, ISilo.CollateralType.Protected);
        emit log_named_decimal_uint(
            string.concat("[", vm.getLabel(protectedShareToken), "] ", vm.getLabel(_user), " protected shares"),
            balance,
            21
        );

        emit log_named_decimal_uint("\tredeemable", redeemable, 21);
        // using balance instead of redeemable to clear out as much shares as we can
        if (redeemable != 0) _silo.redeem(balance, _user, _user, ISilo.CollateralType.Protected);
        vm.stopPrank();
    }

    function _assertShareTokensAreEmpty(ISilo _silo) internal view {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(_silo));

        assertEq(
            IShareToken(protectedShareToken).balanceOf(address(this)),
            0,
            "[_assertShareTokensAreEmpty] protected share token should be 0"
        );
        assertEq(
            IShareToken(collateralShareToken).balanceOf(address(this)),
            0,
            "[_assertShareTokensAreEmpty] collateral share token should be 0"
        );
        assertEq(
            IShareToken(debtShareToken).balanceOf(address(this)),
            0,
            "[_assertShareTokensAreEmpty] debt share token should be 0"
        );
    }

    function _assertProtectedRatioDidNotchanged() internal view {
        assertEq(silo0.convertToShares(1e18, ISilo.AssetType.Protected), 1e21, "silo0 protected ratio");
        assertEq(silo1.convertToShares(1e18, ISilo.AssetType.Protected), 1e21, "silo1 protected ratio");
    }
}
