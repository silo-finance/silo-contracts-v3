// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.28;

import {Math} from "openzeppelin5/utils/math/Math.sol";

import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";

library PartialLiquidationLib {
    using Math for uint256;

    struct LiquidationPreviewParams {
        uint256 collateralLt;
        address collateralConfigAsset;
        address debtConfigAsset;
        uint256 maxDebtToCover;
        uint256 liquidationFee;
        uint256 liquidationTargetLtv;
    }

    /// @dev this is basically LTV == 100%
    uint256 internal constant _BAD_DEBT = 1e18;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    /// @dev underestimation for collateral that user gets on liquidation
    /// liquidation is executed based on sTokens, additional flow is: assets -> shares -> assets
    /// this two conversions are rounding down and can create 2 wai difference
    uint256 internal constant _UNDERESTIMATION = 2;

    /// @dev If the ratio of the repay value to the total debt value during liquidation exceeds the 
    /// _FULL_LIQUIDATION_THRESHOLD threshold, a full liquidation is triggered.
    /// For example, if the total debt value is 51 and the dust level is set at 98%, 
    /// then we are unable to liquidate 50, we must proceed to liquidate the entire 51.
    uint256 internal constant _FULL_LIQUIDATION_THRESHOLD = 0.9e18; // 90%

    /// @dev debt keeps growing over time, so when dApp use this view to calculate max, tx should never revert
    /// because actual max can be only higher
    /// @notice This method does not check, if user is solvent and it can return non zero result when user solvent
    function maxLiquidation(
        uint256 _sumOfCollateralAssets,
        uint256 _sumOfCollateralValue,
        uint256 _borrowerDebtAssets,
        uint256 _borrowerDebtValue,
        uint256 _liquidationTargetLTV,
        uint256 _liquidationFee
    )
        internal
        pure
        returns (uint256 collateralToLiquidate, uint256 debtToRepay)
    {
        (
            uint256 collateralValueToLiquidate, uint256 repayValue
        ) = maxLiquidationPreview(
            _sumOfCollateralValue,
            _borrowerDebtValue,
            _liquidationTargetLTV,
            _liquidationFee
        );

        collateralToLiquidate = valueToAssetsByRatio(
            collateralValueToLiquidate,
            _sumOfCollateralAssets,
            _sumOfCollateralValue
        );

        if (collateralToLiquidate > _UNDERESTIMATION) {
            // -_UNDERESTIMATION here is to underestimate collateral that user gets on liquidation
            // liquidation is executed based on sTokens, additional flow is: assets -> shares -> assets
            // this two conversions are rounding down and can create 2 wei difference

            // we will not underflow on -_UNDERESTIMATION because collateralToLiquidate is >= _UNDERESTIMATION
            unchecked { collateralToLiquidate -= _UNDERESTIMATION; }
        } else {
            collateralToLiquidate = 0;
        }

        debtToRepay = valueToAssetsByRatio(repayValue, _borrowerDebtAssets, _borrowerDebtValue);
    }

    /// @dev in case of bad debt, we do not apply any restrictions.
    /// @notice might revert when one of this values will be zero:
    /// `_sumOfCollateralValue`, `_borrowerDebtAssets`, `_borrowerDebtValue`
    function liquidationPreview( // solhint-disable-line function-max-lines
        uint256 _ltvBefore,
        uint256 _sumOfCollateralAssets,
        uint256 _sumOfCollateralValue,
        uint256 _borrowerDebtAssets,
        uint256 _borrowerDebtValue,
        LiquidationPreviewParams memory _params
    )
        internal
        pure
        returns (uint256 collateralToLiquidate, uint256 debtToRepay, uint256 ltvAfter)
    {
        uint256 collateralValueToLiquidate;
        uint256 debtValueToRepay;

        if (_ltvBefore >= _BAD_DEBT) {
            // in case of bad debt, we allow for any amount
            debtToRepay = _params.maxDebtToCover > _borrowerDebtAssets ? _borrowerDebtAssets : _params.maxDebtToCover;
            debtValueToRepay = valueToAssetsByRatio(debtToRepay, _borrowerDebtValue, _borrowerDebtAssets);
        } else {
            uint256 maxRepayValue = estimateMaxRepayValue(
                _borrowerDebtValue,
                _sumOfCollateralValue,
                _params.liquidationTargetLtv,
                _params.liquidationFee
            );

            if (maxRepayValue == _borrowerDebtValue) {
                // forced full liquidation
                debtToRepay = _borrowerDebtAssets;
                debtValueToRepay = _borrowerDebtValue;
            } else {
                // partial liquidation
                uint256 maxDebtToRepay = valueToAssetsByRatio(maxRepayValue, _borrowerDebtAssets, _borrowerDebtValue);
                debtToRepay = _params.maxDebtToCover > maxDebtToRepay ? maxDebtToRepay : _params.maxDebtToCover;
                debtValueToRepay = valueToAssetsByRatio(debtToRepay, _borrowerDebtValue, _borrowerDebtAssets);
            }
        }

        collateralValueToLiquidate = calculateCollateralToLiquidate(
            debtValueToRepay, _sumOfCollateralValue, _params.liquidationFee
        );

        collateralToLiquidate = valueToAssetsByRatio(
            collateralValueToLiquidate,
            _sumOfCollateralAssets,
            _sumOfCollateralValue
        );

        ltvAfter = _calculateLtvAfter(
            _sumOfCollateralValue, _borrowerDebtValue, collateralValueToLiquidate, debtValueToRepay
        );
    }

    /// @notice reverts on `_totalValue` == 0
    /// @dev calculate assets based on ratio: assets = (value, totalAssets, totalValue)
    /// to calculate assets => value, use it like: value = (assets, totalValue, totalAssets)
    /// this method is used for collateral assets and for debt assets
    function valueToAssetsByRatio(uint256 _value, uint256 _totalAssets, uint256 _totalValue)
        internal
        pure
        returns (uint256 assets)
    {
        require(_totalValue != 0, IPartialLiquidation.UnknownRatio());

        assets = Math.mulDiv(_value, _totalAssets, _totalValue, Rounding.DOWN);
    }

    /// @notice this function never reverts
    /// @dev in case there is not enough collateral to liquidate, whole collateral is returned, no revert
    /// @param  _totalBorrowerCollateralValue can not be 0, otherwise revert
    function calculateCollateralsToLiquidate(
        uint256 _debtValueToCover,
        uint256 _totalBorrowerCollateralValue,
        uint256 _totalBorrowerCollateralAssets,
        uint256 _liquidationFee
    ) internal pure returns (uint256 collateralAssetsToLiquidate, uint256 collateralValueToLiquidate) {
        collateralValueToLiquidate = calculateCollateralToLiquidate(
            _debtValueToCover, _totalBorrowerCollateralValue, _liquidationFee
        );

        // this is also true if _totalBorrowerCollateralValue == 0, so div below will not revert
        if (collateralValueToLiquidate == _totalBorrowerCollateralValue) {
            return (_totalBorrowerCollateralAssets, _totalBorrowerCollateralValue);
        }

        // this will never revert, because of `if collateralValueToLiquidate == _totalBorrowerCollateralValue`
        collateralAssetsToLiquidate = valueToAssetsByRatio(
            collateralValueToLiquidate, _totalBorrowerCollateralAssets, _totalBorrowerCollateralValue
        );
    }

    /// @dev the math is based on: (Dv - x)/(Cv - (x + xf)) = LT
    /// where Dv: debt value, Cv: collateral value, LT: expected LT, f: liquidation fee, x: is value we looking for
    /// @notice in case math fail to calculate repay value, eg when collateral is not enough to cover repay and fee
    /// function will return full debt value and full collateral value, it will not revert. It is up to liquidator
    /// to make decision if it will be profitable
    /// @param _totalBorrowerCollateralValue regular and protected
    /// @param _ltvAfterLiquidation % of `repayValue` that liquidator will use as profit from liquidating
    function maxLiquidationPreview(
        uint256 _totalBorrowerCollateralValue,
        uint256 _totalBorrowerDebtValue,
        uint256 _ltvAfterLiquidation,
        uint256 _liquidationFee
    ) internal pure returns (uint256 collateralValueToLiquidate, uint256 repayValue) {
        repayValue = estimateMaxRepayValue(
            _totalBorrowerDebtValue, _totalBorrowerCollateralValue, _ltvAfterLiquidation, _liquidationFee
        );

        collateralValueToLiquidate = calculateCollateralToLiquidate(
            repayValue, _totalBorrowerCollateralValue, _liquidationFee
        );
    }

    /// @param _maxDebtToCover assets or value, but must be in sync with `_totalCollateral`
    /// @param _sumOfCollateral assets or value, but must be in sync with `_maxDebtToCover`
    /// @return toLiquidate depends on inputs, it might be collateral value or collateral assets
    function calculateCollateralToLiquidate(uint256 _maxDebtToCover, uint256 _sumOfCollateral, uint256 _liquidationFee)
        internal
        pure
        returns (uint256 toLiquidate)
    {
        uint256 fee = _maxDebtToCover * _liquidationFee / _PRECISION_DECIMALS;

        toLiquidate = _maxDebtToCover + fee;

        if (toLiquidate > _sumOfCollateral) {
            toLiquidate = _sumOfCollateral;
        }
    }

    /// @dev the math is based on: (Dv - x)/(Cv - (x + xf)) = LTV
    /// where 
    ///    Dv: debt value,
    ///    Cv: collateral value,
    ///    LTV: expected LTV after liquidation,
    ///    f: liquidation fee,
    ///    x: is value we looking for
    /// x = (Dv - LTV * Cv) / (DP - LTV - LTV * f)
    /// result also take into consideration the dust
    /// @notice protocol does not uses this method, because in protocol our input is debt to cover in assets
    /// however this is useful to figure out what is max debt to cover.
    /// @param _totalBorrowerCollateralValue regular and protected
    /// @param _ltvAfterLiquidation % of `repayValue` that liquidator will use as profit from liquidating
    /// @return repayValue max repay value that is allowed for partial liquidation. if this value equals
    /// `_totalBorrowerDebtValue`, that means dust threshold was triggered and result force to do full liquidation
    function estimateMaxRepayValue( // solhint-disable-line code-complexity
        uint256 _totalBorrowerDebtValue,
        uint256 _totalBorrowerCollateralValue,
        uint256 _ltvAfterLiquidation,
        uint256 _liquidationFee
    ) internal pure returns (uint256 repayValue) {
        if (_totalBorrowerDebtValue == 0) return 0;
        if (_liquidationFee >= _PRECISION_DECIMALS) return 0;

        // this will cover case, when _totalBorrowerCollateralValue == 0
        if (_totalBorrowerDebtValue >= _totalBorrowerCollateralValue) return _totalBorrowerDebtValue;
        if (_ltvAfterLiquidation == 0) return _totalBorrowerDebtValue; // full liquidation

        // x = (Dv - LTV * Cv) / (DP - LTV - LTV * f) ==> (Dv - LTV * Cv) / (DP - (LTV + LTV * f))
        uint256 ltCv = _ltvAfterLiquidation * _totalBorrowerCollateralValue;
        // to lose as low precision as possible, instead of `ltCv/1e18`, we increase precision of DebtValue
        _totalBorrowerDebtValue *= _PRECISION_DECIMALS;

        // negative value means our current LTV is lower than _ltvAfterLiquidation
        if (ltCv >= _totalBorrowerDebtValue) return 0;

        uint256 dividerR; // LTV + LTV * f

        unchecked {
            // safe because of above `LTCv >= _totalBorrowerDebtValue`
            repayValue = _totalBorrowerDebtValue - ltCv;
            // we checked at begin `_liquidationFee >= _PRECISION_DECIMALS`
            // mul on DP will not overflow on uint256, div is safe
            dividerR = _ltvAfterLiquidation + _ltvAfterLiquidation * _liquidationFee / _PRECISION_DECIMALS;
        }

        // now we can go back to proper precision
        unchecked { _totalBorrowerDebtValue /= _PRECISION_DECIMALS; }

        // if dividerR is more than 100%, means it is impossible to go down to _ltvAfterLiquidation, return all
        if (dividerR >= _PRECISION_DECIMALS) {
             return _totalBorrowerDebtValue;
        }

        unchecked { repayValue /= (_PRECISION_DECIMALS - dividerR); }

        // early return so we do not have to check for dust
        if (repayValue > _totalBorrowerDebtValue) return _totalBorrowerDebtValue;

        // here is weird case, sometimes it is impossible to go down to target LTV, however math can calculate it
        // eg with negative numerator and denominator and result will be positive, that's why we simply return all
        // we also cover dust case here
        return repayValue * _PRECISION_DECIMALS / _totalBorrowerDebtValue > _FULL_LIQUIDATION_THRESHOLD
            ? _totalBorrowerDebtValue
            : repayValue;
    }

    /// @dev protected collateral is prioritized
    /// @param _borrowerProtectedAssets available users protected collateral
    function splitReceiveCollateralToLiquidate(uint256 _collateralToLiquidate, uint256 _borrowerProtectedAssets)
        internal
        pure
        returns (uint256 withdrawAssetsFromCollateral, uint256 withdrawAssetsFromProtected)
    {
        if (_collateralToLiquidate == 0) return (0, 0);

        unchecked {
            (
                withdrawAssetsFromCollateral, withdrawAssetsFromProtected
            ) = _collateralToLiquidate > _borrowerProtectedAssets
                // safe to uncheck because of above condition
                ? (_collateralToLiquidate - _borrowerProtectedAssets, _borrowerProtectedAssets)
                : (0, _collateralToLiquidate);
        }
    }

    /// @notice must stay private because this is not for general LTV, only for ltv after internally
    function _calculateLtvAfter(
        uint256 _sumOfCollateralValue,
        uint256 _totalDebtValue,
        uint256 _collateralValueToLiquidate,
        uint256 _debtValueToCover
    )
        private
        pure
        returns (uint256 ltvAfterLiquidation)
    {
        if (_sumOfCollateralValue <= _collateralValueToLiquidate || _totalDebtValue <= _debtValueToCover) {
            return 0;
        }

        unchecked { // all subs are safe because these values are chunks of total, so we will not underflow
            ltvAfterLiquidation = _ltvAfter(
                _sumOfCollateralValue - _collateralValueToLiquidate,
                _totalDebtValue - _debtValueToCover
            );
        }
    }

    /// @notice must stay private because this is not for general LTV, only for ltv after
    function _ltvAfter(uint256 _collateral, uint256 _debt) private pure returns (uint256 ltv) {
        // previous calculation of LTV
        ltv = _debt * _PRECISION_DECIMALS;
        ltv = Math.ceilDiv(ltv, _collateral); // Rounding.LTV is up/ceil
    }
}
