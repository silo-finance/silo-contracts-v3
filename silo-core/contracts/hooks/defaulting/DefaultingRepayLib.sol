// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {ShareTokenLib} from "silo-core/contracts/lib/ShareTokenLib.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

/// @title PartialLiquidationByDefaultingLogic
/// @dev implements custom delegate call logic for Silo
library DefaultingRepayLib {
    using Hook for uint256;
    using Hook for uint24;

    /// @notice Repays a given asset amount and returns the equivalent number of shares
    /// @dev This is a copy of lib/Actions.sol repay() function with a single line changed.
    /// siloLendingLibRepay(), line 48, is used instead of SiloLendingLib.repay().
    /// @param _assets Amount of assets to be repaid
    /// @param _borrower Address of the borrower whose debt is being repaid
    /// @param _repayer Address of the repayer who repay debt
    /// @return assets number of assets that had been repay
    /// @return shares number of shares that had been repay
    // solhint-disable-next-line function-max-lines
    function actionsRepay(uint256 _assets, uint256 _shares, address _borrower, address _repayer)
        external
        returns (uint256 assets, uint256 shares)
    {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        if (_shareStorage.hookSetup.hooksBefore.matchAction(Hook.REPAY)) {
            bytes memory data = abi.encodePacked(_assets, _shares, _borrower, _repayer);
            IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), Hook.REPAY, data);
        }

        ISiloConfig siloConfig = _shareStorage.siloConfig;

        siloConfig.turnOnReentrancyProtection();
        siloConfig.accrueInterestForSilo(address(this));

        (address debtShareToken, address debtAsset) = siloConfig.getDebtShareTokenAndAsset(address(this));

        (assets, shares) = siloLendingLibRepay(
            IShareToken(debtShareToken), debtAsset, _assets, _shares, _borrower, _repayer
        );

        siloConfig.turnOffReentrancyProtection();

        if (_shareStorage.hookSetup.hooksAfter.matchAction(Hook.REPAY)) {
            bytes memory data = abi.encodePacked(_assets, _shares, _borrower, _repayer, assets, shares);
            IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), Hook.REPAY, data);
        }
    }

    /// @dev This is a copy of lib/SiloLendingLib.sol repay() function with a single line changed.
    /// In the last line _debtAsset transfer from repayer is removed.
    function siloLendingLibRepay(
        IShareToken _debtShareToken,
        address, /* _debtAsset */
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

        // _debtAsset transfer from repayer removed.
        // This is the only change in the function in comparison to lib/SiloLendingLib.sol repay() function.
    }
}
