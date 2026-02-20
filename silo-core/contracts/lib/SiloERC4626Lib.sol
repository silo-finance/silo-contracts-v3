// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloConfig} from "../interfaces/ISiloConfig.sol";
import {ISilo} from "../interfaces/ISilo.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {SiloSolvencyLib} from "./SiloSolvencyLib.sol";
import {SiloMathLib} from "./SiloMathLib.sol";
import {SiloLendingLib} from "./SiloLendingLib.sol";
import {Rounding} from "./Rounding.sol";
import {ShareTokenLib} from "./ShareTokenLib.sol";
import {SiloStorageLib} from "./SiloStorageLib.sol";

// solhint-disable function-max-lines

library SiloERC4626Lib {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    /// @dev ERC4626: MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be
    ///      deposited. In our case, we want to limit this value in a way, that after max deposit we can do borrow.
    uint256 internal constant _VIRTUAL_DEPOSIT_LIMIT = type(uint256).max;

    /// @notice Deposit assets into the silo
    /// @param _token The ERC20 token address being deposited; 0 means tokens will not be transferred. Useful for
    /// transition of collateral.
    /// @param _depositor Address of the user depositing the assets
    /// @param _assets Amount of assets being deposited. Use 0 if shares are provided.
    /// @param _shares Shares being exchanged for the deposit; used for precise calculations. Use 0 if assets are
    /// provided.
    /// @param _receiver The address that will receive the collateral shares
    /// @param _collateralShareToken The collateral share token
    /// @param _collateralType The type of collateral being deposited
    /// @return assets The exact amount of assets being deposited
    /// @return shares The exact number of collateral shares being minted in exchange for the deposited assets
    function deposit(
        address _token,
        address _depositor,
        uint256 _assets,
        uint256 _shares,
        address _receiver,
        IShareToken _collateralShareToken,
        ISilo.CollateralType _collateralType
    ) internal returns (uint256 assets, uint256 shares) {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();
        ISilo.AssetType collateralType = ISilo.AssetType(uint256(_collateralType));

        uint256 totalAssets = $.totalAssets[collateralType];

        (assets, shares) = SiloMathLib.convertToAssetsOrToShares(
            _assets,
            _shares,
            totalAssets,
            _collateralShareToken.totalSupply(),
            Rounding.DEPOSIT_TO_ASSETS,
            Rounding.DEPOSIT_TO_SHARES,
            collateralType
        );

        $.totalAssets[collateralType] = totalAssets + assets;

        // Hook receiver is called after `mint` and can reentry but state changes are completed already,
        // and reentrancy protection is still enabled.
        _collateralShareToken.mint(_receiver, _depositor, shares);

        if (_token != address(0)) {
            // Reentrancy is possible only for view methods (read-only reentrancy),
            // so no harm can be done as the state is already updated.
            // We do not expect the silo to work with any malicious token that will not send tokens to silo.
            IERC20(_token).safeTransferFrom(_depositor, address(this), assets);
        }
    }

    /// @notice Withdraw assets from the silo
    /// @dev Asset type is not verified here, make sure you revert before when type == Debt
    /// @param _asset The ERC20 token address to withdraw; 0 means tokens will not be transferred. Useful for
    /// transition of collateral.
    /// @param _shareToken Address of the share token being burned for withdrawal
    /// @param _args ISilo.WithdrawArgs
    /// @return assets The exact amount of assets withdrawn
    /// @return shares The exact number of shares burned in exchange for the withdrawn assets
    function withdraw(
        address _asset,
        address _shareToken,
        ISilo.WithdrawArgs memory _args
    ) internal returns (uint256 assets, uint256 shares) {
        uint256 shareTotalSupply = IShareToken(_shareToken).totalSupply();
        require(shareTotalSupply != 0, ISilo.NothingToWithdraw());

        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        ISilo.AssetType collateralType = ISilo.AssetType(uint256(_args.collateralType));

        { // Stack too deep
            uint256 totalAssets = $.totalAssets[collateralType];

            (assets, shares) = SiloMathLib.convertToAssetsOrToShares(
                _args.assets,
                _args.shares,
                totalAssets,
                shareTotalSupply,
                Rounding.WITHDRAW_TO_ASSETS,
                Rounding.WITHDRAW_TO_SHARES,
                collateralType
            );

            uint256 liquidity = _args.collateralType == ISilo.CollateralType.Collateral
                ? SiloMathLib.liquidity($.totalAssets[ISilo.AssetType.Collateral], $.totalAssets[ISilo.AssetType.Debt])
                : $.totalAssets[ISilo.AssetType.Protected];

            // check liquidity
            require(assets <= liquidity, ISilo.NotEnoughLiquidity());

            $.totalAssets[collateralType] = totalAssets - assets;
        }

        // `burn` checks if `_spender` is allowed to withdraw `_owner` assets. `burn` calls hook receiver
        // after tokens transfer and can potentially reenter, but state changes are already completed,
        // and reentrancy protection is still enabled.
        IShareToken(_shareToken).burn(_args.owner, _args.spender, shares);

        if (_asset != address(0)) {
            // does not matter what is the type of transfer, we can not go below protected balance
            uint256 protectedBalance = $.totalAssets[ISilo.AssetType.Protected];

            require(
                protectedBalance == 0 || IERC20(_asset).balanceOf(address(this)) - assets >= protectedBalance,
                ISilo.ProtectedProtection()
            );

            // fee-on-transfer is ignored
            IERC20(_asset).safeTransfer(_args.receiver, assets);
        }
    }

    /// @notice Determines the maximum amount a user can withdraw, either in terms of assets or shares
    /// @dev The function computes the maximum withdrawable assets and shares, considering user's collateral, debt,
    /// and the liquidity in the silo.
    /// Debt withdrawals are not allowed, resulting in a revert if such an attempt is made.
    /// @param _owner Address of the user for which the maximum withdrawal amount is calculated
    /// @param _collateralType The type of asset being considered for withdrawal
    /// @param _totalAssets The total PROTECTED assets in the silo. In case of collateral use `0`, total
    /// collateral will be calculated internally with interest
    /// @return assets The maximum assets that the user can withdraw
    /// @return shares The maximum shares that the user can withdraw
    function maxWithdraw(
        address _owner,
        ISilo.CollateralType _collateralType,
        uint256 _totalAssets
    ) internal view returns (uint256 assets, uint256 shares) {
        (
            ISiloConfig.DepositConfig memory depositConfig,
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = ShareTokenLib.siloConfig().getConfigsForWithdraw(address(this), _owner);

        uint256 shareTokenTotalSupply;
        uint256 liquidity;

        if (_collateralType == ISilo.CollateralType.Collateral) {
            shareTokenTotalSupply = IShareToken(depositConfig.collateralShareToken).totalSupply();
            (liquidity, _totalAssets, ) = SiloLendingLib.getLiquidityAndAssetsWithInterest(
                depositConfig.interestRateModel,
                depositConfig.daoFee,
                depositConfig.deployerFee
            );

            if (liquidity != 0) {
                // We need to count for fractions. When fractions are applied, liquidity may be decreased.
                unchecked { liquidity -= 1; _totalAssets -= 1; }
            }
        } else {
            shareTokenTotalSupply = IShareToken(depositConfig.protectedShareToken).totalSupply();
            liquidity = _totalAssets;
        }

        // if deposit is not related to debt
        if (depositConfig.silo != collateralConfig.silo) {
            shares = _collateralType == ISilo.CollateralType.Protected
                ? IShareToken(depositConfig.protectedShareToken).balanceOf(_owner)
                : IShareToken(depositConfig.collateralShareToken).balanceOf(_owner);

            assets = SiloMathLib.convertToAssets(
                shares,
                _totalAssets,
                shareTokenTotalSupply,
                Rounding.MAX_WITHDRAW_TO_ASSETS,
                ISilo.AssetType(uint256(_collateralType))
            );

            if (_collateralType == ISilo.CollateralType.Collateral && assets > liquidity) {
                assets = liquidity;

                shares = SiloMathLib.convertToShares(
                    assets,
                    _totalAssets,
                    shareTokenTotalSupply,
                    // when we doing withdraw, we using Rounding.Ceil, because we want to burn as many shares
                    // however here, we will be using shares as input to withdraw, if we round up, we can overflow
                    // because we will want to withdraw too much, so we have to use Rounding.Floor
                    Rounding.MAX_WITHDRAW_TO_SHARES,
                    ISilo.AssetType.Collateral
                );
            }
        } else {
            (assets, shares) = maxWithdrawWhenDebt(
                collateralConfig, debtConfig, _owner, liquidity, shareTokenTotalSupply, _collateralType, _totalAssets
            );
        }

        /*
        there might be a case where conversion from assets <=> shares is not returning same amounts eg:
        convert to shares ==> 1 * (1002 + 1e3) / (2 + 1) = 667.3
        convert to assets ==> 667 * (2 + 1) / (1002 + 1e3) = 0.9995
        so when user will use 667 withdrawal will fail, this is why we have to cross check:
        */
        if (
            SiloMathLib.convertToAssets({
                _shares: shares,
                _totalAssets: _totalAssets,
                _totalShares: shareTokenTotalSupply,
                _rounding: Rounding.MAX_WITHDRAW_TO_ASSETS,
                _assetType: ISilo.AssetType(uint8(_collateralType))
            }) == 0
        ) {
            return (0, 0);
        }
    }

    function maxWithdrawWhenDebt(
        ISiloConfig.ConfigData memory _collateralConfig,
        ISiloConfig.ConfigData memory _debtConfig,
        address _owner,
        uint256 _liquidity,
        uint256 _shareTokenTotalSupply,
        ISilo.CollateralType _collateralType,
        uint256 _totalAssets
    ) internal view returns (uint256 assets, uint256 shares) {
        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.getAssetsDataForLtvCalculations(
            _collateralConfig,
            _debtConfig,
            _owner,
            ISilo.OracleType.Solvency,
            ISilo.AccrueInterestInMemory.Yes,
            IShareToken(_debtConfig.debtShareToken).balanceOf(_owner)
        );

        // Workaround for fractions. We assume the worst case scenario that we will have integral revenue
        // that will be subtracted from collateral and integral interest that will be added to debt.
        {
            // We need to decrease borrowerCollateralAssets
            // since we cannot access totalCollateralAssets before calculations.
            if (ltvData.borrowerCollateralAssets != 0) ltvData.borrowerCollateralAssets--;

            // We need to increase borrowerDebtAssets since we cannot access totalDebtAssets before calculations.
            // If borrowerDebtAssets is 0 then we have no interest
            if (ltvData.borrowerDebtAssets != 0) ltvData.borrowerDebtAssets++;
        }

        {
            (uint256 collateralValue, uint256 debtValue) =
                SiloSolvencyLib.getPositionValues(ltvData, _collateralConfig.token, _debtConfig.token);

            assets = SiloMathLib.calculateMaxAssetsToWithdraw({
                _sumOfCollateralsValue: collateralValue,
                _debtValue: debtValue,
                _lt: _collateralConfig.lt,
                _borrowerCollateralAssets: ltvData.borrowerCollateralAssets,
                _borrowerProtectedAssets: ltvData.borrowerProtectedAssets
            });
        }

        (assets, shares) = SiloMathLib.maxWithdrawToAssetsAndShares({
            _maxAssets: assets,
            _borrowerCollateralAssets: ltvData.borrowerCollateralAssets,
            _borrowerProtectedAssets: ltvData.borrowerProtectedAssets,
            _collateralType: _collateralType,
            _totalAssets: _totalAssets,
            _assetTypeShareTokenTotalSupply: _shareTokenTotalSupply,
            _liquidity: _liquidity
        });

        if (assets != 0) {
            // recalculate assets due to rounding error that we have in convertToShares
            assets = SiloMathLib.convertToAssets(
                shares,
                _totalAssets,
                _shareTokenTotalSupply,
                Rounding.MAX_WITHDRAW_TO_ASSETS,
                ISilo.AssetType(uint256(_collateralType))
            );
        }
    }
}
