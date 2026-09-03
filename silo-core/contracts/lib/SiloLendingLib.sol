// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.28;

// solhint-disable ordering

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloOracle} from "../interfaces/ISiloOracle.sol";
import {ISilo} from "../interfaces/ISilo.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {ISiloConfig} from "../interfaces/ISiloConfig.sol";
import {SiloSolvencyLib} from "./SiloSolvencyLib.sol";
import {SiloStdLib} from "./SiloStdLib.sol";
import {SiloMathLib} from "./SiloMathLib.sol";
import {Rounding} from "./Rounding.sol";
import {ShareTokenLib} from "./ShareTokenLib.sol";
import {SiloStorageLib} from "./SiloStorageLib.sol";

library SiloLendingLib {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;
    /// @dev If SILO has low total debt, interest might be lost to rounding for low deposits.
    /// Value is based on minimal deposit needed to accrue two digit wei interest for 1 second at 0.01% APR.
    /// Example of calculations for 1 second at 0.01% APR and totalDebtAssets 1e13:
    /// 1e13 * (0.0001/365/24/3600*1e18) * 1 / 1e18 = 31.70979198376459
    uint256 internal constant _ROUNDING_THRESHOLD = 1e13;

    /// @notice Allows repaying borrowed assets either partially or in full
    /// @param _debtShareToken debt share token address
    /// @param _debtAsset underlying debt asset address
    /// @param _assets The amount of assets to repay. Use 0 if shares are used.
    /// @param _shares The number of corresponding shares associated with the debt. Use 0 if assets are used.
    /// @param _borrower The account that has the debt
    /// @param _repayer The account that is repaying the debt
    /// @return assets The amount of assets that was repaid
    /// @return shares The corresponding number of debt shares that were repaid
    function repay(
        IShareToken _debtShareToken,
        address _debtAsset,
        uint256 _assets,
        uint256 _shares,
        address _borrower,
        address _repayer
    ) internal returns (uint256 assets, uint256 shares) {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        uint256 totalDebtAssets = $.totalAssets[ISilo.AssetType.Debt];
        (uint256 debtSharesBalance, uint256 totalDebtShares) = _debtShareToken.balanceOfAndTotalSupply(_borrower);

        (assets, shares) = SiloMathLib.convertToAssetsOrToShares({
            _assets: _assets,
            _shares: _shares,
            _totalAssets: totalDebtAssets,
            _totalShares: totalDebtShares,
            _roundingToAssets: Rounding.REPAY_TO_ASSETS,
            _roundingToShares: Rounding.REPAY_TO_SHARES,
            _assetType: ISilo.AssetType.Debt
        });

        if (shares > debtSharesBalance) {
            shares = debtSharesBalance;

            (assets, shares) = SiloMathLib.convertToAssetsOrToShares({
                _assets: 0,
                _shares: shares,
                _totalAssets: totalDebtAssets,
                _totalShares: totalDebtShares,
                _roundingToAssets: Rounding.REPAY_TO_ASSETS,
                _roundingToShares: Rounding.REPAY_TO_SHARES,
                _assetType: ISilo.AssetType.Debt
            });
        }

        require(totalDebtAssets >= assets, ISilo.RepayTooHigh());

        // subtract repayment from debt, save to unchecked because of above `totalDebtAssets < assets`
        unchecked { $.totalAssets[ISilo.AssetType.Debt] = totalDebtAssets - assets; }

        // Anyone can repay anyone's debt so no approval check is needed.
        _debtShareToken.burn(_borrower, _repayer, shares);
        // fee-on-transfer is ignored
        // Reentrancy is possible only for view methods (read-only reentrancy),
        // so no harm can be done as the state is already updated.
        // We do not expect the silo to work with any malicious token that will not send tokens back.
        IERC20(_debtAsset).safeTransferFrom(_repayer, address(this), assets);
    }

    /// @notice Accrues interest on assets, updating the collateral and debt balances
    /// @dev This method will accrue interest for ONE asset ONLY, to calculate for both silos you have to call it twice
    /// with `_configData` for each token
    /// @param _interestRateModel The address of the interest rate model to calculate the compound interest rate
    /// @param _daoFee DAO's fee in 18 decimals points
    /// @param _deployerFee Deployer's fee in 18 decimals points
    /// @return accruedInterest The total amount of interest accrued
    // solhint-disable-next-line function-max-lines
    function accrueInterestForAsset(address _interestRateModel, uint256 _daoFee, uint256 _deployerFee)
        external
        returns (uint256 accruedInterest)
    {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        uint64 lastTimestamp = $.interestRateTimestamp;

        // Interest has already been accrued this block
        if (lastTimestamp == block.timestamp) {
            return 0;
        }

        // This is the first time, so we can return early and save some gas
        if (lastTimestamp == 0) {
            $.interestRateTimestamp = uint64(block.timestamp);
            return 0;
        }

        uint256 totalFees;
        uint256 totalCollateralAssets = $.totalAssets[ISilo.AssetType.Collateral];
        uint256 totalDebtAssets = $.totalAssets[ISilo.AssetType.Debt];

        uint256 rcomp = getCompoundInterestRate({
            _interestRateModel: _interestRateModel,
            _totalCollateralAssets: totalCollateralAssets,
            _totalDebtAssets: totalDebtAssets,
            _lastTimestamp: lastTimestamp
        });

        if (rcomp == 0) {
            $.interestRateTimestamp = uint64(block.timestamp);
            return 0;
        }

        (
            $.totalAssets[ISilo.AssetType.Collateral], $.totalAssets[ISilo.AssetType.Debt], totalFees, accruedInterest
        ) = SiloMathLib.getCollateralAmountsWithInterest({
            _collateralAssets: totalCollateralAssets,
            _debtAssets: totalDebtAssets,
            _rcomp: rcomp,
            _daoFee: _daoFee,
            _deployerFee: _deployerFee
        });

        (accruedInterest, totalFees) = applyFractions({
            _totalDebtAssets: totalDebtAssets,
            _rcomp: rcomp,
            _accruedInterest: accruedInterest,
            _fees: _daoFee + _deployerFee,
            _totalFees: totalFees
        });

        // update remaining contract state
        $.interestRateTimestamp = uint64(block.timestamp);

        // we operating on chunks (fees) of real tokens, so overflow should not happen
        // fee is simply too small to overflow on cast to uint192, even if, we will get lower fee
        // forge-lint: disable-next-line(unsafe-typecast)
        unchecked { $.daoAndDeployerRevenue += uint192(totalFees); }
    }

    /// @notice Allows a user or a delegate to borrow assets against their collateral
    /// @dev The function checks for necessary conditions such as borrow possibility, enough liquidity, and zero
    /// values
    /// @param _debtShareToken address of debt share token
    /// @param _token address of underlying debt token
    /// @param _spender Address which initiates the borrowing action on behalf of the borrower
    /// @return borrowedAssets Actual number of assets that the user has borrowed
    /// @return borrowedShares Number of debt share tokens corresponding to the borrowed assets
    function borrow(
        address _debtShareToken,
        address _token,
        address _spender,
        ISilo.BorrowArgs memory _args
    )
        internal
        returns (uint256 borrowedAssets, uint256 borrowedShares)
    {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        uint256 totalDebtAssets = $.totalAssets[ISilo.AssetType.Debt];

        (borrowedAssets, borrowedShares) = SiloMathLib.convertToAssetsOrToShares(
            _args.assets,
            _args.shares,
            totalDebtAssets,
            IShareToken(_debtShareToken).totalSupply(),
            Rounding.BORROW_TO_ASSETS,
            Rounding.BORROW_TO_SHARES,
            ISilo.AssetType.Debt
        );

        uint256 totalCollateralAssets = $.totalAssets[ISilo.AssetType.Collateral];

        require(
            _token == address(0) || borrowedAssets <= SiloMathLib.liquidity(totalCollateralAssets, totalDebtAssets),
            ISilo.NotEnoughLiquidity()
        );

        // add new debt
        $.totalAssets[ISilo.AssetType.Debt] = totalDebtAssets + borrowedAssets;

        // `mint` checks if _spender is allowed to borrow on the account of _borrower.
        IShareToken(_debtShareToken).mint(_args.borrower, _spender, borrowedShares);

        if (_token != address(0)) {
            // fee-on-transfer is ignored.
            IERC20(_token).safeTransfer(_args.receiver, borrowedAssets);
        }
    }

    /// @notice Determines the maximum amount (both in assets and shares) that a borrower can borrow
    /// @param _collateralConfig Configuration data for the collateral
    /// @param _debtConfig Configuration data for the debt
    /// @param _borrower The address of the borrower whose maximum borrow limit is being queried
    /// @param _totalDebtAssets The total debt assets in the system
    /// @param _totalDebtShares The total debt shares in the system
    /// @param _siloConfig address of SiloConfig contract
    /// @return assets The maximum amount in assets that can be borrowed
    /// @return shares The equivalent amount in shares for the maximum assets that can be borrowed
    function calculateMaxBorrow( // solhint-disable-line function-max-lines
        ISiloConfig.ConfigData memory _collateralConfig,
        ISiloConfig.ConfigData memory _debtConfig,
        address _borrower,
        uint256 _totalDebtAssets,
        uint256 _totalDebtShares,
        ISiloConfig _siloConfig
    )
        internal
        view
        returns (uint256 assets, uint256 shares)
    {
        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.getAssetsDataForLtvCalculations({
            _collateralConfig: _collateralConfig,
            _debtConfig: _debtConfig,
            _borrower: _borrower,
            _oracleType: ISilo.OracleType.MaxLtv,
            _accrueInMemory: ISilo.AccrueInterestInMemory.Yes,
            _debtShareBalanceCached: 0 /* no cache */
        });

        // Workaround for fractions. We assume the worst case scenario that we will have integral revenue
        // that will be subtracted from collateral and integral interest that will be added to debt.
        {
            // We need to decrease borrowerCollateralAssets
            // since we cannot access totalCollateralAssets before calculations.
            if (ltvData.borrowerCollateralAssets != 0) ltvData.borrowerCollateralAssets--;

            // We need to increase borrowerDebtAssets since we cannot access totalDebtAssets before calculations.
            // If borrowerDebtAssets is 0 then we have no interest
            if (ltvData.borrowerDebtAssets != 0) ltvData.borrowerDebtAssets++;

            // It _totalDebtAssets is 0 then we have no interest
            if (_totalDebtAssets != 0) _totalDebtAssets++;
        }

        (
            uint256 sumOfBorrowerCollateralValue, uint256 borrowerDebtValue
        ) = SiloSolvencyLib.getPositionValues(ltvData, _collateralConfig.token, _debtConfig.token);

        uint256 maxBorrowValue = SiloMathLib.calculateMaxBorrowValue(
            _collateralConfig.maxLtv,
            sumOfBorrowerCollateralValue,
            borrowerDebtValue
        );

        (assets, shares) = maxBorrowValueToAssetsAndShares({
            _maxBorrowValue: maxBorrowValue,
            _debtAsset: _debtConfig.token,
            _debtOracle: ltvData.debtOracle,
            _totalDebtAssets: _totalDebtAssets,
            _totalDebtShares: _totalDebtShares
        });

        if (assets == 0 || shares == 0) return (0, 0);

        uint256 liquidityWithInterest = getLiquidity(_siloConfig);

        if (liquidityWithInterest != 0) {
            // We need to count for fractions, when fractions are applied liquidity may be decreased
            unchecked { liquidityWithInterest -= 1; }
        }

        if (assets > liquidityWithInterest) {
            assets = liquidityWithInterest;

            // rounding must follow same flow as in `maxBorrowValueToAssetsAndShares()`
            shares = SiloMathLib.convertToShares(
                assets,
                _totalDebtAssets,
                _totalDebtShares,
                Rounding.MAX_BORROW_TO_SHARES,
                ISilo.AssetType.Debt
            );
        }
    }

    function maxBorrow(address _borrower)
        internal
        view
        returns (uint256 maxAssets, uint256 maxShares)
    {
        ISiloConfig siloConfig = ShareTokenLib.siloConfig();
        if (siloConfig.hasDebtInOtherSilo(address(this), _borrower)) return (0, 0);

        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = siloConfig.getConfigsForBorrow({_debtSilo: address(this)});

        (uint256 totalDebtAssets, uint256 totalDebtShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(debtConfig, ISilo.AssetType.Debt);

        return calculateMaxBorrow(
            collateralConfig,
            debtConfig,
            _borrower,
            totalDebtAssets,
            totalDebtShares,
            siloConfig
        );
    }

    function getLiquidity(ISiloConfig _siloConfig) internal view returns (uint256 liquidity) {
        ISiloConfig.ConfigData memory config = _siloConfig.getConfig(address(this));
        (liquidity,,) = getLiquidityAndAssetsWithInterest(config.interestRateModel, config.daoFee, config.deployerFee);
    }

    function getLiquidityAndAssetsWithInterest(address _interestRateModel, uint256 _daoFee, uint256 _deployerFee)
        internal
        view
        returns (uint256 liquidity, uint256 totalCollateralAssets, uint256 totalDebtAssets)
    {
        totalCollateralAssets = SiloStdLib.getTotalCollateralAssetsWithInterest(
            address(this),
            _interestRateModel,
            _daoFee,
            _deployerFee
        );

        totalDebtAssets = SiloStdLib.getTotalDebtAssetsWithInterest(
            address(this),
            _interestRateModel
        );

        liquidity = SiloMathLib.liquidity(totalCollateralAssets, totalDebtAssets);
    }

    /// @notice Calculates the maximum borrowable assets and shares
    /// @param _maxBorrowValue The maximum value that can be borrowed by the user
    /// @param _debtAsset Address of the debt token
    /// @param _debtOracle Oracle used to get the value of the debt token
    /// @param _totalDebtAssets Total assets of the debt
    /// @param _totalDebtShares Total shares of the debt
    /// @return assets Maximum borrowable assets
    /// @return shares Maximum borrowable shares
    // solhint-disable-next-line function-max-lines
    function maxBorrowValueToAssetsAndShares(
        uint256 _maxBorrowValue,
        address _debtAsset,
        ISiloOracle _debtOracle,
        uint256 _totalDebtAssets,
        uint256 _totalDebtShares
    )
        internal
        view
        returns (uint256 assets, uint256 shares)
    {
        if (_maxBorrowValue == 0) {
            return (0, 0);
        }

        uint256 debtTokenSample = _PRECISION_DECIMALS;

        uint256 debtSampleValue = address(_debtOracle) == address(0)
            ? debtTokenSample
            : _debtOracle.quote(debtTokenSample, _debtAsset);

        assets = _maxBorrowValue.mulDiv(debtTokenSample, debtSampleValue, Rounding.MAX_BORROW_TO_ASSETS);

        // when we borrow, we convertToShares with rounding.Up, to create higher debt, however here,
        // when we want to calculate "max borrow", we can not round.Up, because it can create issue with max ltv,
        // because we not creating debt here, we calculating max assets/shares, so we need to round.Down here
        shares = SiloMathLib.convertToShares(
            assets, _totalDebtAssets, _totalDebtShares, Rounding.MAX_BORROW_TO_SHARES, ISilo.AssetType.Debt
        );

        {
            /*
            This is a workaround for handling fractions:

            - Fractions are not applied in view methods, so we need to account for them manually.
            - `_totalDebtAssets` is incremented earlier to compensate for these fractions.

            Due to this, increasing `_totalDebtAssets` raises the debt share price. As a result, converting
            assets to shares yields fewer shares, and this same reduced ratio is applied
            to the next conversion (shown below). Ultimately, this means we receive fewer shares for the same amount
            of assets.

            When we call `borrow(assets)` and there are no fractions to apply, `_totalDebtAssets` is not incremented.
            A lower `_totalDebtAssets` means a lower share price, so the same amount of assets
            (as calculated by `maxBorrow()`) will result in more shares. At the final step, when checking maxLtv,
            having more shares translates to more assets—exceeding the allowed maximum LTV.

            Solution:
            Having fewer shares is acceptable because it underestimates the value due to missing fractions.
            When recalculating assets (due to the issue described above), we want a lower share price
            (which occurs when there are no fractions), as this leads to fewer assets and keeps us within the LTV limit.

            Therefore, we decrement `_totalDebtAssets` with `_totalDebtAssets--`
            to offset the earlier `_totalDebtAssets++`.
            */
            if (_totalDebtAssets != 0) {
                unchecked { _totalDebtAssets--; }
            }
        }

        // we need to recalculate assets, because what we did above is assets => shares with rounding down, but when
        // we input assets, they will generate more shares, so we need to calculate assets based on final shares
        // not based on borrow value
        assets = SiloMathLib.convertToAssets(
            shares, _totalDebtAssets, _totalDebtShares, Rounding.MAX_BORROW_TO_ASSETS, ISilo.AssetType.Debt
        );
    }

    function getCompoundInterestRate(
        address _interestRateModel,
        uint256 _totalCollateralAssets,
        uint256 _totalDebtAssets,
        uint64 _lastTimestamp
    ) internal returns (uint256 rcomp) {
        try
            IInterestRateModel(_interestRateModel).getCompoundInterestRateAndUpdate(
                _totalCollateralAssets,
                _totalDebtAssets,
                _lastTimestamp
            )
            returns (uint256 interestRate)
        {
            rcomp = interestRate;
        } catch {
            // do not lock silo on interest calculation
            emit IInterestRateModel.InterestRateModelError();
        }
    }

    function applyFractions(
        uint256 _totalDebtAssets,
        uint256 _rcomp,
        uint256 _accruedInterest,
        uint256 _fees,
        uint256 _totalFees
    )
        internal returns (uint256 accruedInterest, uint256 totalFees)
    {
        // if _totalDebtAssets is greater than _ROUNDING_THRESHOLD then we don't need to worry
        // about precision because there is enough amount of debt to generate double wei digit
        // of interest per second so we can safely ignore fractions
        if (_totalDebtAssets >= _ROUNDING_THRESHOLD) return (_accruedInterest, _totalFees);

        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();
        uint256 totalCollateralAssets = $.totalAssets[ISilo.AssetType.Collateral];

        // `accrueInterestForAsset` should never revert,
        // so we check edge cases for revert and do early return
        // instead of checking each calculation individually for underflow/overflow
        if (totalCollateralAssets == type(uint256).max || totalCollateralAssets == 0) {
            return (_accruedInterest, _totalFees);
        }

        ISilo.Fractions memory fractions = $.fractions;

        uint256 integralInterest;
        uint256 integralRevenue;

        (
            integralInterest, fractions.interest
        ) = SiloMathLib.calculateFraction(_totalDebtAssets, _rcomp, fractions.interest);

        accruedInterest = _accruedInterest + integralInterest;

        (
            integralRevenue, fractions.revenue
        ) = SiloMathLib.calculateFraction(accruedInterest, _fees, fractions.revenue);

        totalFees = _totalFees + integralRevenue;

        $.fractions = fractions;
        $.totalAssets[ISilo.AssetType.Debt] += integralInterest;
        $.totalAssets[ISilo.AssetType.Collateral] = totalCollateralAssets + integralInterest - integralRevenue;
    }
}
