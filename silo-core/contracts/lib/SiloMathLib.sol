// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// solhint-disable ordering

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Rounding} from "../lib/Rounding.sol";
import {ISilo} from "../interfaces/ISilo.sol";

library SiloMathLib {
    using Math for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    uint256 internal constant _DECIMALS_OFFSET = 3;

    /// @dev this is constant version of openzeppelin5/contracts/token/ERC20/extensions/ERC4626._decimalsOffset
    uint256 internal constant _DECIMALS_OFFSET_POW = 10 ** _DECIMALS_OFFSET;

    /// @notice Returns available liquidity to be borrowed
    /// @dev Accrued interest is entirely added to `debtAssets` but only part of it is added to `collateralAssets`. The
    ///      difference is DAO's and deployer's cut. That means DAO's and deployer's cut is not considered a borrowable
    ///      liquidity.
    function liquidity(uint256 _collateralAssets, uint256 _debtAssets) internal pure returns (uint256 liquidAssets) {
        unchecked {
            // we checked the underflow
            liquidAssets = _debtAssets > _collateralAssets ? 0 : _collateralAssets - _debtAssets;
        }
    }

    /// @notice Calculate collateral assets with accrued interest and associated fees
    /// @param _collateralAssets The total amount of collateral assets
    /// @param _debtAssets The total amount of debt assets
    /// @param _rcomp Compound interest rate for debt
    /// @param _daoFee The fee (in 18 decimals points) to be taken for the DAO
    /// @param _deployerFee The fee (in 18 decimals points) to be taken for the deployer
    /// @return collateralAssetsWithInterest The total collateral assets including the accrued interest
    /// @return debtAssetsWithInterest The debt assets with accrued interest
    /// @return daoAndDeployerRevenue Total fees amount to be split between DAO and deployer
    /// @return accruedInterest The total accrued interest
    function getCollateralAmountsWithInterest(
        uint256 _collateralAssets,
        uint256 _debtAssets,
        uint256 _rcomp,
        uint256 _daoFee,
        uint256 _deployerFee
    )
        internal
        pure
        returns (
            uint256 collateralAssetsWithInterest,
            uint256 debtAssetsWithInterest,
            uint256 daoAndDeployerRevenue,
            uint256 accruedInterest
        )
    {
        (debtAssetsWithInterest, accruedInterest) = getDebtAmountsWithInterest(_debtAssets, _rcomp);

        uint256 fees;

        // _daoFee and _deployerFee are expected to be less than 1e18, so we will not overflow
        unchecked { fees = _daoFee + _deployerFee; }

        daoAndDeployerRevenue = mulDivOverflow(accruedInterest, fees, _PRECISION_DECIMALS);

        // we will not underflow because daoAndDeployerRevenue is chunk of accruedInterest
        uint256 collateralInterest = accruedInterest - daoAndDeployerRevenue;

        uint256 cap;
        // save to uncheck because variable can not be more than max
        unchecked { cap = type(uint256).max - _collateralAssets; }

        if (cap < collateralInterest) {
            // avoid overflow on interest
            collateralInterest = cap;
        }

        // safe to uncheck because of cap
        unchecked {  collateralAssetsWithInterest = _collateralAssets + collateralInterest; }
    }

    /// @notice Calculate the debt assets with accrued interest, it should never revert with over/under flow
    /// @param _totalDebtAssets The total amount of debt assets before accrued interest
    /// @param _rcomp Compound interest rate for the debt in 18 decimal precision
    /// @return debtAssetsWithInterest The debt assets including the accrued interest
    /// @return accruedInterest The total amount of interest accrued on the debt assets
    function getDebtAmountsWithInterest(uint256 _totalDebtAssets, uint256 _rcomp)
        internal
        pure
        returns (uint256 debtAssetsWithInterest, uint256 accruedInterest)
    {
        if (_totalDebtAssets == 0 || _rcomp == 0) {
            return (_totalDebtAssets, 0);
        }

        accruedInterest = mulDivOverflow(_totalDebtAssets, _rcomp, _PRECISION_DECIMALS);

        unchecked {
            // We intentionally allow overflow here, to prevent transaction revert due to interest calculation.
            debtAssetsWithInterest = _totalDebtAssets + accruedInterest;

            // If overflow occurs, we skip accruing interest.
            if (debtAssetsWithInterest < _totalDebtAssets) {
                debtAssetsWithInterest = _totalDebtAssets;
                accruedInterest = 0;
            }
        }
    }

    /// @notice Calculates fraction between borrowed and deposited amount of tokens denominated in percentage
    /// @dev It assumes `_dp` = 100%.
    /// @param _dp decimal points used by model
    /// @param _collateralAssets current total deposits for assets
    /// @param _debtAssets current total borrows for assets
    /// @return utilization value, capped to 100%
    /// Limiting utilization ratio by 100% max will allows us to perform better interest rate computations
    /// and should not affect any other part of protocol. It is possible to go over 100% only when bad debt.
    function calculateUtilization(uint256 _dp, uint256 _collateralAssets, uint256 _debtAssets)
        internal
        pure
        returns (uint256 utilization)
    {
        if (_collateralAssets == 0 || _debtAssets == 0 || _dp == 0) return 0;

        /*
            how to prevent overflow on: _debtAssets.mulDiv(_dp, _collateralAssets, Rounding.ACCRUED_INTEREST):
            1. max > _debtAssets * _dp / _collateralAssets
            2. max / _dp > _debtAssets / _collateralAssets
        */
        if (type(uint256).max / _dp > _debtAssets / _collateralAssets) {
            utilization = _debtAssets.mulDiv(_dp, _collateralAssets, Rounding.ACCRUED_INTEREST);
            // cap at 100%
            if (utilization > _dp) utilization = _dp;
        } else {
            // we have overflow
            utilization = _dp;
        }
    }

    function convertToAssetsOrToShares(
        uint256 _assets,
        uint256 _shares,
        uint256 _totalAssets,
        uint256 _totalShares,
        Math.Rounding _roundingToAssets,
        Math.Rounding _roundingToShares,
        ISilo.AssetType _assetType
    ) internal pure returns (uint256 assets, uint256 shares) {
        if (_assets == 0) {
            require(_shares != 0, ISilo.InputZeroShares());
            shares = _shares;
            assets = convertToAssets(_shares, _totalAssets, _totalShares, _roundingToAssets, _assetType);
            require(assets != 0, ISilo.ReturnZeroAssets());
        } else if (_shares == 0) {
            shares = convertToShares(_assets, _totalAssets, _totalShares, _roundingToShares, _assetType);
            assets = _assets;
            require(shares != 0, ISilo.ReturnZeroShares());
        } else {
            revert ISilo.InputCanBeAssetsOrShares();
        }
    }

    /// @dev Math for collateral is exact copy of
    ///      openzeppelin5/contracts/token/ERC20/extensions/ERC4626._convertToShares
    function convertToShares(
        uint256 _assets,
        uint256 _totalAssets,
        uint256 _totalShares,
        Math.Rounding _rounding,
        ISilo.AssetType _assetType
    ) internal pure returns (uint256 shares) {
        (uint256 totalShares, uint256 totalAssets) = _commonConvertTo(_totalAssets, _totalShares, _assetType);

        // initially, in case of debt, if silo is empty we return shares==assets
        // for collateral, this will never be the case, because we are adding `+1` and offset in `_commonConvertTo`
        if (totalShares == 0) return _assets;

        shares = _assets.mulDiv(totalShares, totalAssets, _rounding);
    }

    /// @dev Math for collateral is exact copy of
    ///      openzeppelin5/contracts/token/ERC20/extensions/ERC4626._convertToAssets
    function convertToAssets(
        uint256 _shares,
        uint256 _totalAssets,
        uint256 _totalShares,
        Math.Rounding _rounding,
        ISilo.AssetType _assetType
    ) internal pure returns (uint256 assets) {
        (uint256 totalShares, uint256 totalAssets) = _commonConvertTo(_totalAssets, _totalShares, _assetType);

        // initially, in case of debt, if silo is empty we return shares==assets
        // for collateral, this will never be the case, because of `+1` in line above
        if (totalShares == 0) return _shares;

        assets = _shares.mulDiv(totalAssets, totalShares, _rounding);
    }

    /// @param _collateralMaxLtv maxLTV in 18 decimals that is set for debt asset
    /// @param _sumOfBorrowerCollateralValue borrower total collateral value (including protected)
    /// @param _borrowerDebtValue total value of borrower debt
    /// @return maxBorrowValue max borrow value yet available for borrower
    function calculateMaxBorrowValue(
        uint256 _collateralMaxLtv,
        uint256 _sumOfBorrowerCollateralValue,
        uint256 _borrowerDebtValue
    ) internal pure returns (uint256 maxBorrowValue) {
        if (_sumOfBorrowerCollateralValue == 0) {
            return 0;
        }

        uint256 maxDebtValue = _sumOfBorrowerCollateralValue.mulDiv(
            _collateralMaxLtv, _PRECISION_DECIMALS, Rounding.MAX_BORROW_VALUE
        );

        unchecked {
            // we will not underflow because we checking `maxDebtValue > _borrowerDebtValue`
            maxBorrowValue = maxDebtValue > _borrowerDebtValue ? maxDebtValue - _borrowerDebtValue : 0;
        }
    }

    /// @notice Calculate the maximum assets a borrower can withdraw without breaching the liquidation threshold
    /// @param _sumOfCollateralsValue The combined value of collateral and protected assets of the borrower
    /// @param _debtValue The total debt value of the borrower
    /// @param _lt The liquidation threshold in 18 decimal points
    /// @param _borrowerCollateralAssets The borrower's collateral assets before the withdrawal
    /// @param _borrowerProtectedAssets The borrower's protected assets before the withdrawal
    /// @return maxAssets The maximum assets the borrower can safely withdraw
    function calculateMaxAssetsToWithdraw(
        uint256 _sumOfCollateralsValue,
        uint256 _debtValue,
        uint256 _lt,
        uint256 _borrowerCollateralAssets,
        uint256 _borrowerProtectedAssets
    ) internal pure returns (uint256 maxAssets) {
        if (_sumOfCollateralsValue == 0) return 0;
        if (_debtValue == 0) return _sumOfCollateralsValue;
        if (_lt == 0) return 0;

        // using Rounding.LT (up) to have highest collateralValue that we have to leave for user to stay solvent
        uint256 minimumCollateralValue = _debtValue.mulDiv(_PRECISION_DECIMALS, _lt, Rounding.LTV);

        // if we over LT, we can not withdraw
        if (_sumOfCollateralsValue <= minimumCollateralValue) {
            return 0;
        }

        uint256 spareCollateralValue;
        // safe because we checked `if (_sumOfCollateralsValue <= minimumCollateralValue)`
        unchecked { spareCollateralValue = _sumOfCollateralsValue - minimumCollateralValue; }

        maxAssets = (_borrowerProtectedAssets + _borrowerCollateralAssets)
                .mulDiv(spareCollateralValue, _sumOfCollateralsValue, Rounding.MAX_WITHDRAW_TO_ASSETS);
    }

    /// @notice Determines the maximum number of assets and corresponding shares a borrower can safely withdraw
    /// @param _maxAssets The calculated limit on how many assets can be withdrawn without breaching the liquidation
    /// threshold
    /// @param _borrowerCollateralAssets Amount of collateral assets currently held by the borrower
    /// @param _borrowerProtectedAssets Amount of protected assets currently held by the borrower
    /// @param _collateralType Specifies whether the asset is of type Collateral or Protected
    /// @param _totalAssets The entire quantity of assets available in the system for withdrawal
    /// @param _assetTypeShareTokenTotalSupply Total supply of share tokens for the specified asset type
    /// @param _liquidity Current liquidity in the system for the asset type
    /// @return assets Maximum assets the borrower can withdraw
    /// @return shares Corresponding number of shares for the derived `assets` amount
    function maxWithdrawToAssetsAndShares(
        uint256 _maxAssets,
        uint256 _borrowerCollateralAssets,
        uint256 _borrowerProtectedAssets,
        ISilo.CollateralType _collateralType,
        uint256 _totalAssets,
        uint256 _assetTypeShareTokenTotalSupply,
        uint256 _liquidity
    ) internal pure returns (uint256 assets, uint256 shares) {
        if (_maxAssets == 0) return (0, 0);
        if (_assetTypeShareTokenTotalSupply == 0) return (0, 0);

        if (_collateralType == ISilo.CollateralType.Collateral) {
            assets = _maxAssets > _borrowerCollateralAssets ? _borrowerCollateralAssets : _maxAssets;

            if (assets > _liquidity) {
                assets = _liquidity;
            }
        } else {
            assets = _maxAssets > _borrowerProtectedAssets ? _borrowerProtectedAssets : _maxAssets;
        }

        shares = SiloMathLib.convertToShares(
            assets,
            _totalAssets,
            _assetTypeShareTokenTotalSupply,
            Rounding.MAX_WITHDRAW_TO_SHARES,
            ISilo.AssetType(uint256(_collateralType))
        );
    }

    /// @dev executed `_a * _b / _c`, reverts on _c == 0
    /// @return mulDivResult on overflow returns 0
    function mulDivOverflow(uint256 _a, uint256 _b, uint256 _c)
        internal
        pure
        returns (uint256 mulDivResult)
    {
        if (_a == 0) return (0);

        unchecked {
            // we have to uncheck to detect overflow
            mulDivResult = _a * _b;
            if (mulDivResult / _a != _b) return 0;

            mulDivResult /= _c;
        }
    }

    /// @dev Debt calculations should not lower the result. Debt is a liability so protocol should not take any for
    /// itself. It should return actual result and round it up.
    function _commonConvertTo(
        uint256 _totalAssets,
        uint256 _totalShares,
        ISilo.AssetType _assetType
    ) private pure returns (uint256 totalShares, uint256 totalAssets) {
        if (_totalShares == 0) {
            // silo is empty and we have dust to redistribute: this can only happen when everyone exits silo
            // this case can happen only for collateral, because for collateral we rounding in favorite of protocol
            // by resetting totalAssets, the dust that we have will go to first depositor and we starts from clean state
            _totalAssets = 0;
        }

            (totalShares, totalAssets) = _assetType == ISilo.AssetType.Debt
                ? (_totalShares, _totalAssets)
                : (_totalShares + _DECIMALS_OFFSET_POW, _totalAssets + 1);
    }

    /// @dev Calculates the fraction of a given total and percentage
    /// @param _total The total value to calculate the fraction from
    /// @param _percent The percentage to calculate the fraction from
    /// @param _currentFraction The current fraction to add to the result
    /// @return integral The integral part of the fraction
    /// @return fraction The fractional part of the fraction
    function calculateFraction(
        uint256 _total,
        uint256 _percent,
        uint64 _currentFraction
    ) internal pure returns (uint256 integral, uint64 fraction) {
        if (_total == 0) {
            return (0, _currentFraction);
        }

        unchecked {
            // safe to unchecked because: _currentFraction if never more than max uint256, div is safe
            if (type(uint256).max / _total < _percent) {
                // when overflow, reset `_currentFraction ` to zero as part of circuit breaker
                return (0, 0);
            }

            // `_total * _percent` safe to unchecked because we checked for overflow in above `if`
            // `% _PRECISION_DECIMALS` safe, because max value after modulo will be 1e18 - 1  (_PRECISION_DECIMALS - 1)
            // and this is less than 2 ** 64
            // calculate remainder for current interest
            uint256 remainder = (_total * _percent) % _PRECISION_DECIMALS;
            // integral is amount above 1e18 after adding _currentFraction and remainder
            integral = (_currentFraction + remainder) / _PRECISION_DECIMALS;
            // fraction is what we get below 1e18
            // Safe: modulo by `_PRECISION_DECIMALS` guarantees value <= 1e18 - 1, far below uint64 max.
            // forge-lint: disable-next-line(unsafe-typecast)
            fraction = uint64((_currentFraction + remainder) % _PRECISION_DECIMALS);
        }
    }
}
