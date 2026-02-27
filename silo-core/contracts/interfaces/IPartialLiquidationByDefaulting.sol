// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISilo} from "./ISilo.sol";
import {ISiloIncentivesController} from "../incentives/interfaces/ISiloIncentivesController.sol";

/// @notice Partial liquidation by defaulting will cancel borrower debt and distribute collateral shares 
/// to lenders via incentive contract. Lenders have to claim their shares to get them. 
/// Executor will get liquidation fee directly on his wallet.
/// Partial liquidation by defaulting can reset total assets completely while leaving shares behind. 
/// In that case, all shares will be worth 0 and next deposit will lose the value of that left shares.
/// Partial liquidation by defaulting can deduct collateral by 1 wei more than debt. This can happen 
/// when we doing full liquidation and conversion assets -> shares -> assets loses 1 wei.
interface IPartialLiquidationByDefaulting {
    struct CallParams {
        uint256 collateralSharesTotal;
        uint256 protectedSharesTotal;
        uint256 withdrawAssetsFromCollateral;
        uint256 withdrawAssetsFromProtected;
        uint256 collateralSharesForKeeper;
        uint256 collateralSharesForLenders;
        uint256 protectedSharesForKeeper;
        uint256 protectedSharesForLenders;
        bytes4 customError;
    }
    
    /// @param canceledDebt amount of debt that was canceled by liquidation
    /// @param deductedFromCollateral amount of collateral that was deducted from collateral, 
    /// it might be lower then debt eg in case of bad debt
    event DefaultingLiquidation(uint256 canceledDebt, uint256 deductedFromCollateral);

    event DefaultingLiquidationData(address indexed silo, address indexed borrower, uint256 repayDebtAssets, uint256 withdrawCollateral);

    error NoControllerForCollateral();
    error CollateralNotSupportedForDefaulting();
    error TwoWayMarketNotAllowed();
    error UnnecessaryLiquidationFee();
    error EmptyCollateralShareToken();
    error DeductDefaultedDebtFromCollateralFailed();
    error RepayDebtByDefaultingFailed();
    error InvalidLTConfig0();
    error InvalidLTConfig1();

    /// @notice Function to liquidate insolvent position by distributing user's collateral to lenders
    /// The caller (liquidator) does not cover any debt. `debtToCover` is amount of debt being liquidated
    ///   based on which amount of `collateralAsset` is calculated to distribute to lenders plus a liquidation fee.
    ///   Liquidation fee is split 80/20 between lenders and liquidator.
    /// Defaulting liquidation can leave dust shares behind, because math uses assets, 
    /// and dust shares are worth less than 1 asset.
    /// @dev this method reverts when:
    /// - `_maxDebtToCover` is zero
    /// - `_user` is solvent and there is no debt to cover
    /// - oracle is throwing (might be also because of tiny position eg 1wei)
    /// - `_borrower` is solvent in terms of defaulting (might be insolvent for standard liquidation)
    /// - on ReturnZeroShares error
    /// - when asset:share ratio is such that 1 asset does not equal at least 1 share eg: 
    ///    totalAssets = 100, totalShares = 10, assetsToLiquidate = 1
    /// @param _user The address of the borrower getting liquidated
    /// @return withdrawCollateral collateral that was send to `msg.sender`, in case of `_receiveSToken` is TRUE,
    /// `withdrawCollateral` will be estimated, on redeem one can expect this value to be rounded down
    /// @return repayDebtAssets actual debt value that was repaid by `msg.sender`
    function liquidationCallByDefaulting(address _user)
        external
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets);

    /// @dev it can revert in case of assets or shares values close to max uint256
    function getKeeperAndLenderSharesSplit(
        uint256 _assetsToLiquidate,
        ISilo.CollateralType _collateralType
    ) external view returns (uint256 totalSharesToLiquidate, uint256 keeperShares, uint256 lendersShares);

    /// @notice Validate if market is supported by defaulting, reverts if not
    function validateDefaultingCollateral() external view;

    /// @notice Validate if gauge controller (silo incentives controller) is set for debt silo, reverts if not
    /// @param _silo The address of the silo from which debt is borrowed
    /// @return controllerCollateral The address of the gauge for debt silo
    function validateControllerForCollateral(address _silo)
        external
        view
        returns (ISiloIncentivesController controllerCollateral);

    /// @dev Additional liquidation threshold (LT) margin applied during defaulting liquidations
    /// to give priority to traditional liquidations over defaulting ones. Expressed in 18 decimals.
    // solhint-disable-next-line func-name-mixedcase
    function LT_MARGIN_FOR_DEFAULTING() external view returns (uint256);

    /// @dev Address of the DefaultingSiloLogic contract used by Silo for delegate calls
    // solhint-disable-next-line func-name-mixedcase
    function LIQUIDATION_LOGIC() external view returns (address);

    /// @dev The portion of total liquidation fee proceeds allocated to the keeper. Expressed in 18 decimals.
    /// For example, liquidation fee is 10% (0.1e18), and keeper fee is 20% (0.2e18),
    /// then 2% liquidation fee goes to the keeper and 8% goes to the protocol.
    // solhint-disable-next-line func-name-mixedcase
    function KEEPER_FEE() external view returns (uint256);   
}
