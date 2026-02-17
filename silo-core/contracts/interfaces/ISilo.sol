// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IERC4626, IERC20, IERC20Metadata} from "openzeppelin5/interfaces/IERC4626.sol";

import {IERC3156FlashLender} from "./IERC3156FlashLender.sol";
import {ISiloConfig} from "./ISiloConfig.sol";
import {ISiloFactory} from "./ISiloFactory.sol";

import {IHookReceiver} from "./IHookReceiver.sol";

// solhint-disable ordering
interface ISilo is IERC20, IERC4626, IERC3156FlashLender {
    /// @dev Interest accrual happens on each deposit/withdraw/borrow/repay. View methods work on storage that might be
    ///      outdate. Some calculations require accrued interest to return current state of Silo. This struct is used
    ///      to make a decision inside functions if interest should be accrued in memory to work on updated values.
    enum AccrueInterestInMemory {
        No,
        Yes
    }

    /// @dev Silo has two separate oracles for solvency and maxLtv calculations. MaxLtv oracle is optional. Solvency
    ///      oracle can also be optional if asset is used as denominator in Silo config. For example, in ETH/USDC Silo
    ///      one could setup only solvency oracle for ETH that returns price in USDC. Then USDC does not need an oracle
    ///      because it's used as denominator for ETH and it's "price" can be assume as 1.
    enum OracleType {
        Solvency,
        MaxLtv
    }

    /// @dev There are 3 types of accounting in the system: for non-borrowable collateral deposit called "protected",
    ///      for borrowable collateral deposit called "collateral" and for borrowed tokens called "debt". System does
    ///      identical calculations for each type of accounting but it uses different data. To avoid code duplication
    ///      this enum is used to decide which data should be read.
    enum AssetType {
        Protected, // default
        Collateral,
        Debt
    }

    /// @dev There are 2 types of accounting in the system: for non-borrowable collateral deposit called "protected" and
    ///      for borrowable collateral deposit called "collateral". System does
    ///      identical calculations for each type of accounting but it uses different data. To avoid code duplication
    ///      this enum is used to decide which data should be read.
    enum CollateralType {
        Protected, // default
        Collateral
    }

    /// @dev Types of calls that can be made by the hook receiver on behalf of Silo via `callOnBehalfOfSilo` fn
    enum CallType {
        Call, // default
        Delegatecall
    }

    /// @param _assets Amount of assets the user wishes to withdraw. Use 0 if shares are provided.
    /// @param _shares Shares the user wishes to burn in exchange for the withdrawal. Use 0 if assets are provided.
    /// @param _receiver Address receiving the withdrawn assets
    /// @param _owner Address of the owner of the shares being burned
    /// @param _spender Address executing the withdrawal; may be different than `_owner` if an allowance was set
    /// @param _collateralType Type of the asset being withdrawn (Collateral or Protected)
    struct WithdrawArgs {
        uint256 assets;
        uint256 shares;
        address receiver;
        address owner;
        address spender;
        ISilo.CollateralType collateralType;
    }

    /// @param assets Number of assets the borrower intends to borrow. Use 0 if shares are provided.
    /// @param shares Number of shares corresponding to the assets that the borrower intends to borrow. Use 0 if
    /// assets are provided.
    /// @param receiver Address that will receive the borrowed assets
    /// @param borrower The user who is borrowing the assets
    struct BorrowArgs {
        uint256 assets;
        uint256 shares;
        address receiver;
        address borrower;
    }

    /// @param shares Amount of shares the user wishes to transit.
    /// @param owner owner of the shares after transition.
    /// @param transitionFrom type of collateral that will be transitioned.
    struct TransitionCollateralArgs {
        uint256 shares;
        address owner;
        ISilo.CollateralType transitionFrom;
    }

    struct UtilizationData {
        /// @dev COLLATERAL: Amount of asset token that has been deposited to Silo plus interest earned by depositors.
        /// It also includes token amount that has been borrowed.
        uint256 collateralAssets;
        /// @dev DEBT: Amount of asset token that has been borrowed plus accrued interest.
        uint256 debtAssets;
        /// @dev timestamp of the last interest accrual
        uint64 interestRateTimestamp;
    }

    /// @dev Interest and revenue may be rounded down to zero if the underlying token's decimal is low.
    /// Because of that, we need to store fractions for further calculation to minimize losses.
    struct Fractions {
        /// @dev interest value that we could not convert to full token in 36 decimals, max value for it is 1e18.
        /// this value was not yet apply as interest for borrowers
        uint64 interest;
        /// @dev revenue value that we could not convert to full token in 36 decimals, max value for it is 1e18.
        uint64 revenue;
    }

    struct SiloStorage {
        /// @param daoAndDeployerRevenue Current amount of assets (fees) accrued by DAO and Deployer
        /// but not yet withdrawn
        uint192 daoAndDeployerRevenue;
        /// @dev timestamp of the last interest accrual
        uint64 interestRateTimestamp;
        /// @dev Interest and revenue fractions for more precise calculations
        Fractions fractions;

        /// @dev silo is just for one asset,
        /// but this one asset can be of three types: mapping key is uint256(AssetType), so we store `assets` by type.
        /// Assets based on type:
        /// - PROTECTED COLLATERAL: Amount of asset token that has been deposited to Silo that can be ONLY used
        /// as collateral. These deposits do NOT earn interest and CANNOT be borrowed.
        /// - COLLATERAL: Amount of asset token that has been deposited to Silo plus interest earned by depositors.
        /// It also includes token amount that has been borrowed.
        /// - DEBT: Amount of asset token that has been borrowed plus accrued interest.
        /// `totalAssets` can have outdated value (without interest), if you doing view call (of off-chain call)
        /// please use getters eg `getCollateralAssets()` to fetch value that includes interest.
        mapping(AssetType assetType => uint256 assets) totalAssets;
    }

    /// @notice Emitted on protected deposit
    /// @param sender wallet address that deposited asset
    /// @param owner wallet address that received shares in Silo
    /// @param assets amount of asset that was deposited
    /// @param shares amount of shares that was minted
    event DepositProtected(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Emitted on protected withdraw
    /// @param sender wallet address that sent transaction
    /// @param receiver wallet address that received asset
    /// @param owner wallet address that owned asset
    /// @param assets amount of asset that was withdrew
    /// @param shares amount of shares that was burn
    event WithdrawProtected(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Emitted on borrow
    /// @param sender wallet address that sent transaction
    /// @param receiver wallet address that received asset
    /// @param owner wallet address that owes assets
    /// @param assets amount of asset that was borrowed
    /// @param shares amount of shares that was minted
    event Borrow(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Emitted on repayment
    /// @param sender wallet address that repaid asset
    /// @param owner wallet address that owed asset
    /// @param assets amount of asset that was repaid
    /// @param shares amount of shares that was burn
    event Repay(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice emitted only when collateral has been switched to other one
    event CollateralTypeChanged(address indexed borrower);

    event HooksUpdated(uint24 hooksBefore, uint24 hooksAfter);

    event AccruedInterest(uint256 hooksBefore);

    event FlashLoan(uint256 amount);

    event WithdrawnFees(uint256 daoFees, uint256 deployerFees, bool redirectedDeployerFees);

    event DeployerFeesRedirected(uint256 deployerFees);

    error UnsupportedFlashloanToken();
    error FlashloanAmountTooBig();
    error NothingToWithdraw();
    error ProtectedProtection();
    error NotEnoughLiquidity();
    error NotSolvent();
    error BorrowNotPossible();
    error EarnedZero();
    error FlashloanFailed();
    error AboveMaxLtv();
    error SiloInitialized();
    error OnlyHookReceiver();
    error NoLiquidity();
    error InputCanBeAssetsOrShares();
    error CollateralSiloAlreadySet();
    error RepayTooHigh();
    error ZeroAmount();
    error InputZeroShares();
    error ReturnZeroAssets();
    error ReturnZeroShares();
    error Deprecated();

    /// @return siloFactory The associated factory of the silo
    function factory() external view returns (ISiloFactory siloFactory);

    /// @notice Method for HookReceiver only to call on behalf of Silo
    /// @param _target address of the contract to call
    /// @param _value amount of ETH to send
    /// @param _callType type of the call (Call or Delegatecall)
    /// @param _input calldata for the call
    function callOnBehalfOfSilo(address _target, uint256 _value, CallType _callType, bytes calldata _input)
        external
        payable
        returns (bool success, bytes memory result);

    /// @notice Initialize Silo
    /// @param _siloConfig address of ISiloConfig with full config for this Silo
    function initialize(ISiloConfig _siloConfig) external;

    /// @notice Update hooks configuration for Silo
    /// @dev This function must be called after the hooks configuration is changed in the hook receiver
    function updateHooks() external;

    /// @notice Fetches the silo configuration contract
    /// @return siloConfig Address of the configuration contract associated with the silo
    function config() external view returns (ISiloConfig siloConfig);

    /// @notice Fetches the utilization data of the silo used by IRM
    function utilizationData() external view returns (UtilizationData memory utilizationData);

    /// @notice Fetches the real (available to borrow) liquidity in the silo, it does include interest
    /// @return liquidity The amount of liquidity
    function getLiquidity() external view returns (uint256 liquidity);

    /// @notice Determines if a borrower is solvent
    /// @param _borrower Address of the borrower to check for solvency
    /// @return True if the borrower is solvent, otherwise false
    function isSolvent(address _borrower) external view returns (bool);

    /// @notice Retrieves the raw total amount of assets based on provided type (direct storage access)
    function getTotalAssetsStorage(AssetType _assetType) external view returns (uint256);

    /// @notice Direct storage access to silo storage
    /// @dev See struct `SiloStorage` for more details
    function getSiloStorage()
        external
        view
        returns (
            uint192 daoAndDeployerRevenue,
            uint64 interestRateTimestamp,
            uint256 protectedAssets,
            uint256 collateralAssets,
            uint256 debtAssets
        );

    /// @notice Direct access to silo storage fractions variables
    function getFractionsStorage() external view returns (Fractions memory fractions);

    /// @notice Retrieves the total amount of collateral (borrowable) assets with interest
    /// @return totalCollateralAssets The total amount of assets of type 'Collateral'
    function getCollateralAssets() external view returns (uint256 totalCollateralAssets);

    /// @notice Retrieves the total amount of debt assets with interest
    /// @return totalDebtAssets The total amount of assets of type 'Debt'
    function getDebtAssets() external view returns (uint256 totalDebtAssets);

    /// @notice Retrieves the total amounts of collateral and protected (non-borrowable) assets
    /// @return totalCollateralAssets The total amount of assets of type 'Collateral'
    /// @return totalProtectedAssets The total amount of protected (non-borrowable) assets
    function getCollateralAndProtectedTotalsStorage()
        external
        view
        returns (uint256 totalCollateralAssets, uint256 totalProtectedAssets);

    /// @notice Retrieves the total amounts of collateral and debt assets
    /// @return totalCollateralAssets The total amount of assets of type 'Collateral'
    /// @return totalDebtAssets The total amount of debt assets of type 'Debt'
    function getCollateralAndDebtTotalsStorage()
        external
        view
        returns (uint256 totalCollateralAssets, uint256 totalDebtAssets);

    /// @notice Implements IERC4626.convertToShares for each asset type
    function convertToShares(uint256 _assets, AssetType _assetType) external view returns (uint256 shares);

    /// @notice Implements IERC4626.convertToAssets for each asset type
    function convertToAssets(uint256 _shares, AssetType _assetType) external view returns (uint256 assets);

    /// @notice Implements IERC4626.previewDeposit for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function previewDeposit(uint256 _assets, CollateralType _collateralType) external view returns (uint256 shares);

    /// @notice Implements IERC4626.deposit for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function deposit(uint256 _assets, address _receiver, CollateralType _collateralType)
        external
        returns (uint256 shares);

    /// @notice Implements IERC4626.previewMint for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function previewMint(uint256 _shares, CollateralType _collateralType) external view returns (uint256 assets);

    /// @notice Implements IERC4626.mint for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function mint(uint256 _shares, address _receiver, CollateralType _collateralType) external returns (uint256 assets);

    /// @notice Implements IERC4626.maxWithdraw for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function maxWithdraw(address _owner, CollateralType _collateralType) external view returns (uint256 maxAssets);

    /// @notice Implements IERC4626.previewWithdraw for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function previewWithdraw(uint256 _assets, CollateralType _collateralType) external view returns (uint256 shares);

    /// @notice Implements IERC4626.withdraw for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function withdraw(uint256 _assets, address _receiver, address _owner, CollateralType _collateralType)
        external
        returns (uint256 shares);

    /// @notice Implements IERC4626.maxRedeem for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function maxRedeem(address _owner, CollateralType _collateralType) external view returns (uint256 maxShares);

    /// @notice Implements IERC4626.previewRedeem for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function previewRedeem(uint256 _shares, CollateralType _collateralType) external view returns (uint256 assets);

    /// @notice Implements IERC4626.redeem for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function redeem(uint256 _shares, address _receiver, address _owner, CollateralType _collateralType)
        external
        returns (uint256 assets);

    /// @notice Calculates the maximum amount of assets that can be borrowed by the given address
    /// @param _borrower Address of the potential borrower
    /// @return maxAssets Maximum amount of assets that the borrower can borrow, this value is underestimated
    /// That means, in some cases when you borrow maxAssets, you will be able to borrow again eg. up to 2wei
    /// Reason for underestimation is to return value that will not cause borrow revert
    function maxBorrow(address _borrower) external view returns (uint256 maxAssets);

    /// @notice Previews the amount of shares equivalent to the given asset amount for borrowing
    /// @param _assets Amount of assets to preview the equivalent shares for
    /// @return shares Amount of shares equivalent to the provided asset amount
    function previewBorrow(uint256 _assets) external view returns (uint256 shares);

    /// @notice Allows an address to borrow a specified amount of assets
    /// @param _assets Amount of assets to borrow
    /// @param _receiver Address receiving the borrowed assets
    /// @param _borrower Address responsible for the borrowed assets
    /// @return shares Amount of shares equivalent to the borrowed assets
    function borrow(uint256 _assets, address _receiver, address _borrower)
        external returns (uint256 shares);

    /// @notice Calculates the maximum amount of shares that can be borrowed by the given address
    /// @param _borrower Address of the potential borrower
    /// @return maxShares Maximum number of shares that the borrower can borrow
    function maxBorrowShares(address _borrower) external view returns (uint256 maxShares);

    /// @notice Previews the amount of assets equivalent to the given share amount for borrowing
    /// @param _shares Amount of shares to preview the equivalent assets for
    /// @return assets Amount of assets equivalent to the provided share amount
    function previewBorrowShares(uint256 _shares) external view returns (uint256 assets);

    /// @notice deprecated
    function maxBorrowSameAsset(address _borrower) external view returns (uint256 maxAssets);

    /// @notice deprecated
    function borrowSameAsset(uint256 _assets, address _receiver, address _borrower)
        external returns (uint256 shares);

    /// @notice Allows a user to borrow assets based on the provided share amount
    /// @param _shares Amount of shares to borrow against
    /// @param _receiver Address to receive the borrowed assets
    /// @param _borrower Address responsible for the borrowed assets
    /// @return assets Amount of assets borrowed
    function borrowShares(uint256 _shares, address _receiver, address _borrower)
        external
        returns (uint256 assets);

    /// @notice Calculates the maximum amount an address can repay based on their debt shares
    /// @param _borrower Address of the borrower
    /// @return assets Maximum amount of assets the borrower can repay
    function maxRepay(address _borrower) external view returns (uint256 assets);

    /// @notice Provides an estimation of the number of shares equivalent to a given asset amount for repayment
    /// @param _assets Amount of assets to be repaid
    /// @return shares Estimated number of shares equivalent to the provided asset amount
    function previewRepay(uint256 _assets) external view returns (uint256 shares);

    /// @notice Repays a given asset amount and returns the equivalent number of shares
    /// @param _assets Amount of assets to be repaid
    /// @param _borrower Address of the borrower whose debt is being repaid
    /// @return shares The equivalent number of shares for the provided asset amount
    function repay(uint256 _assets, address _borrower) external returns (uint256 shares);

    /// @notice Calculates the maximum number of shares that can be repaid for a given borrower
    /// @param _borrower Address of the borrower
    /// @return shares The maximum number of shares that can be repaid for the borrower
    function maxRepayShares(address _borrower) external view returns (uint256 shares);

    /// @notice Provides a preview of the equivalent assets for a given number of shares to repay
    /// @param _shares Number of shares to preview repayment for
    /// @return assets Equivalent assets for the provided shares
    function previewRepayShares(uint256 _shares) external view returns (uint256 assets);

    /// @notice Allows a user to repay a loan using shares instead of assets
    /// @param _shares The number of shares the borrower wants to repay with
    /// @param _borrower The address of the borrower for whom to repay the loan
    /// @return assets The equivalent assets amount for the provided shares
    function repayShares(uint256 _shares, address _borrower) external returns (uint256 assets);

    /// @notice Transitions assets between borrowable (collateral) and non-borrowable (protected) states
    /// @dev This function allows assets to move between collateral and protected (non-borrowable) states without
    /// leaving the protocol
    /// @param _shares Amount of shares to be transitioned
    /// @param _owner Owner of the assets being transitioned
    /// @param _transitionFrom Specifies if the transition is from collateral or protected assets
    /// @return assets Amount of assets transitioned
    function transitionCollateral(uint256 _shares, address _owner, CollateralType _transitionFrom)
        external
        returns (uint256 assets);

    /// @notice deprecated
    function switchCollateralToThisSilo() external;

    /// @notice Accrues interest for the asset and returns the accrued interest amount
    /// @return accruedInterest The total interest accrued during this operation
    function accrueInterest() external returns (uint256 accruedInterest);

    /// @notice only for SiloConfig
    function accrueInterestForConfig(
        address _interestRateModel,
        uint256 _daoFee,
        uint256 _deployerFee
    ) external;

    /// @notice Withdraws earned fees and distributes them to the DAO and deployer fee receivers
    function withdrawFees() external;
}
