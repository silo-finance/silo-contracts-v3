// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";
import {ERC4626, Math} from "openzeppelin5/token/ERC20/extensions/ERC4626.sol";
import {IERC4626, IERC20, IERC20Metadata} from "openzeppelin5/interfaces/IERC4626.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {ERC20Permit} from "openzeppelin5/token/ERC20/extensions/ERC20Permit.sol";
import {Multicall} from "openzeppelin5/utils/Multicall.sol";
import {ERC20} from "openzeppelin5/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {UtilsLib} from "morpho-blue/libraries/UtilsLib.sol";

import {
    MarketConfig,
    ArbitraryLossThreshold,
    PendingUint192,
    PendingAddress,
    MarketAllocation,
    ISiloVaultBase,
    ISiloVaultStaticTyping
} from "./interfaces/ISiloVault.sol";

import {INotificationReceiver} from "./interfaces/INotificationReceiver.sol";
import {IVaultIncentivesModule} from "./interfaces/IVaultIncentivesModule.sol";
import {IIncentivesClaimingLogic} from "./interfaces/IIncentivesClaimingLogic.sol";

import {PendingUint192, PendingAddress, PendingLib} from "./libraries/PendingLib.sol";
import {ConstantsLib} from "./libraries/ConstantsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {SiloVaultActionsLib} from "./libraries/SiloVaultActionsLib.sol";

/// @title SiloVault
/// @dev Forked with gratitude from Morpho Labs.
/// @author Silo Labs
/// @custom:contact security@silo.finance
/// @notice ERC4626 compliant vault allowing users to deposit assets to any ERC4626 vault.
contract SiloVault is ERC4626, ERC20Permit, Ownable2Step, Multicall, ISiloVaultStaticTyping {
    uint256 constant WAD = 1e18;

    using Math for uint256;
    using SafeERC20 for IERC20;
    using PendingLib for PendingUint192;
    using PendingLib for PendingAddress;

    /* IMMUTABLES */

    /// @inheritdoc ISiloVaultBase
    uint256 public constant DEFAULT_LOST_THRESHOLD = 1e6;

    /// @inheritdoc ISiloVaultBase
    uint8 public constant DECIMALS_OFFSET = 6;

    /// @inheritdoc ISiloVaultBase
    IVaultIncentivesModule public immutable INCENTIVES_MODULE;

    /* STORAGE */

    /// @inheritdoc ISiloVaultBase
    address public curator;

    /// @inheritdoc ISiloVaultBase
    mapping(address => bool) public isAllocator;

    /// @inheritdoc ISiloVaultBase
    address public guardian;

    /// @inheritdoc ISiloVaultStaticTyping
    mapping(IERC4626 => MarketConfig) public config;

    /// @inheritdoc ISiloVaultBase
    uint256 public timelock;

    /// @inheritdoc ISiloVaultStaticTyping
    PendingAddress public pendingGuardian;

    /// @inheritdoc ISiloVaultStaticTyping
    mapping(IERC4626 => PendingUint192) public pendingCap;

    /// @inheritdoc ISiloVaultStaticTyping
    PendingUint192 public pendingTimelock;

    /// @dev Internal balance tracker to prevent assets loss if the underlying market is hacked
    /// and starts reporting wrong supply.
    /// max loss == supplyCap + un accrued interest.
    mapping(IERC4626 => uint256) public balanceTracker;

    /// @notice Configurable arbitrary loss threshold for each market that
    /// will be used in the `_priceManipulationCheck` fn to prevent assets loss.
    mapping(IERC4626 => ArbitraryLossThreshold) public arbitraryLossThreshold;

    /// @inheritdoc ISiloVaultBase
    uint96 public fee;

    /// @inheritdoc ISiloVaultBase
    address public feeRecipient;

    /// @inheritdoc ISiloVaultBase
    IERC4626[] public supplyQueue;

    /// @inheritdoc ISiloVaultBase
    IERC4626[] public withdrawQueue;

    /// @inheritdoc ISiloVaultBase
    uint256 public lastTotalAssets;

    /// @dev Reentrancy guard.
    bool transient _lock;

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param _owner The owner of the contract.
    /// @param _initialTimelock The initial timelock.
    /// @param _vaultIncentivesModule The vault incentives module.
    /// @param _asset The address of the underlying asset.
    /// @param _name The name of the vault.
    /// @param _symbol The symbol of the vault.
    constructor(
        address _owner,
        uint256 _initialTimelock,
        IVaultIncentivesModule _vaultIncentivesModule,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(IERC20(_asset)) ERC20Permit(_name) ERC20(_name, _symbol) Ownable(_owner) {
        require(address(_vaultIncentivesModule) != address(0), ErrorsLib.ZeroAddress());
        require(decimals() <= 18, ErrorsLib.NotSupportedDecimals());

        _checkTimelockBounds(_initialTimelock);
        _setTimelock(_initialTimelock);
        INCENTIVES_MODULE = _vaultIncentivesModule;
    }

    /* MODIFIERS */

    /// @dev Reverts if the caller doesn't have the curator role.
    modifier onlyCuratorRole() {
        address sender = _msgSender();
        if (sender != curator && sender != owner()) revert ErrorsLib.NotCuratorRole();

        _;
    }

    /// @dev Reverts if the caller doesn't have the allocator role.
    modifier onlyAllocatorRole() {
        address sender = _msgSender();
        if (!isAllocator[sender] && sender != curator && sender != owner()) {
            revert ErrorsLib.NotAllocatorRole();
        }

        _;
    }

    /// @dev Reverts if the caller doesn't have the guardian role.
    modifier onlyGuardianRole() {
        if (_msgSender() != owner() && _msgSender() != guardian) revert ErrorsLib.NotGuardianRole();

        _;
    }

    /// @dev Reverts if the caller doesn't have the curator nor the guardian role.
    modifier onlyCuratorOrGuardianRole() {
        if (_msgSender() != guardian && _msgSender() != curator && _msgSender() != owner()) {
            revert ErrorsLib.NotCuratorNorGuardianRole();
        }

        _;
    }

    /// @dev Makes sure conditions are met to accept a pending value.
    /// @dev Reverts if:
    /// - there's no pending value;
    /// - the timelock has not elapsed since the pending value has been submitted.
    modifier afterTimelock(uint256 _validAt) {
        if (_validAt == 0) revert ErrorsLib.NoPendingValue();
        if (block.timestamp < _validAt) revert ErrorsLib.TimelockNotElapsed();

        _;
    }

    /* ONLY OWNER FUNCTIONS */

    /// @inheritdoc ISiloVaultBase
    function setCurator(address _newCurator) external virtual onlyOwner {
        if (_newCurator == curator) revert ErrorsLib.AlreadySet();

        curator = _newCurator;

        emit EventsLib.SetCurator(_newCurator);
    }

    /// @inheritdoc ISiloVaultBase
    function setIsAllocator(address _newAllocator, bool _newIsAllocator) external virtual onlyOwner {
        SiloVaultActionsLib.setIsAllocator(_newAllocator, _newIsAllocator, isAllocator);
    }

    /// @inheritdoc ISiloVaultBase
    function submitTimelock(uint256 _newTimelock) external virtual onlyOwner {
        if (_newTimelock == timelock) revert ErrorsLib.AlreadySet();
        if (pendingTimelock.validAt != 0) revert ErrorsLib.AlreadyPending();
        _checkTimelockBounds(_newTimelock);

        if (_newTimelock > timelock) {
            _setTimelock(_newTimelock);
        } else {
            // Safe "unchecked" cast because newTimelock <= MAX_TIMELOCK.
            // forge-lint: disable-next-line(unsafe-typecast)
            pendingTimelock.update(uint184(_newTimelock), timelock);

            emit EventsLib.SubmitTimelock(_newTimelock);
        }
    }

    /// @inheritdoc ISiloVaultBase
    function setFee(uint256 _newFee) external virtual onlyOwner {
        // Accrue fee using the previous fee set before changing it.
        _updateLastTotalAssets(_accrueFee());

        SiloVaultActionsLib.setFeeValidateEmitEvent(_newFee, fee, feeRecipient);

        // Safe to cast because newFee <= MAX_FEE.
        // forge-lint: disable-next-line(unsafe-typecast)
        fee = uint96(_newFee);
    }

    /// @inheritdoc ISiloVaultBase
    function setFeeRecipient(address _newFeeRecipient) external virtual onlyOwner {
        // Accrue fee to the previous fee recipient set before changing it.
        _updateLastTotalAssets(_accrueFee());

        SiloVaultActionsLib.validateFeeRecipientEmitEvent(_newFeeRecipient, feeRecipient, fee);

        feeRecipient = _newFeeRecipient;
    }

    /// @inheritdoc ISiloVaultBase
    function submitGuardian(address _newGuardian) external virtual onlyOwner {
        if (_newGuardian == guardian) revert ErrorsLib.AlreadySet();
        if (pendingGuardian.validAt != 0) revert ErrorsLib.AlreadyPending();

        if (guardian == address(0)) {
            _setGuardian(_newGuardian);
        } else {
            SiloVaultActionsLib.updatePendingGuardian(pendingGuardian, _newGuardian, timelock);
        }
    }

    /* ONLY GUARDIAN FUNCTIONS */

    /// @inheritdoc ISiloVaultBase
    function setArbitraryLossThreshold(IERC4626 _market, uint256 _lossThreshold) external virtual onlyGuardianRole {
        SiloVaultActionsLib.setArbitraryLossThreshold(_lossThreshold, arbitraryLossThreshold[_market]);
    }

    /// @inheritdoc ISiloVaultBase
    function syncBalanceTracker(
        IERC4626 _market,
        uint256 _expectedAssets,
        bool _override
    ) external virtual onlyGuardianRole {
        SiloVaultActionsLib.syncBalanceTracker(balanceTracker, _market, _expectedAssets, _override);
    }

    /* ONLY CURATOR FUNCTIONS */

    /// @inheritdoc ISiloVaultBase
    function submitCap(IERC4626 _market, uint256 _newSupplyCap) external virtual onlyCuratorRole {
        uint256 supplyCap = SiloVaultActionsLib.submitCapValidate(_market, _newSupplyCap, asset(), config, pendingCap);

        if (_newSupplyCap < supplyCap) {
            _setCap(_market, SafeCast.toUint184(_newSupplyCap));
        } else {
            pendingCap[_market].update(SafeCast.toUint184(_newSupplyCap), timelock);

            emit EventsLib.SubmitCap(_msgSender(), _market, _newSupplyCap);
        }
    }

    /// @inheritdoc ISiloVaultBase
    function submitMarketRemoval(IERC4626 _market) external virtual onlyCuratorRole {
        SiloVaultActionsLib.submitMarketRemoval(_market, config, pendingCap, timelock);
    }

    /* ONLY ALLOCATOR FUNCTIONS */

    /// @inheritdoc ISiloVaultBase
    function setSupplyQueue(IERC4626[] calldata _newSupplyQueue) external virtual onlyAllocatorRole {
        _nonReentrantOn();

        SiloVaultActionsLib.validateSupplyQueueEmitEvent(_newSupplyQueue, config);

        supplyQueue = _newSupplyQueue;

        _nonReentrantOff();
    }

    /// @inheritdoc ISiloVaultBase
    function updateWithdrawQueue(uint256[] calldata _indexes) external virtual onlyAllocatorRole {
        _nonReentrantOn();

        withdrawQueue = SiloVaultActionsLib.updateWithdrawQueue(config, pendingCap, withdrawQueue, _indexes);

        _nonReentrantOff();
    }

    /// @inheritdoc ISiloVaultBase
    function reallocate(MarketAllocation[] calldata _allocations) external virtual onlyAllocatorRole {
        _nonReentrantOn();

        uint256 totalSupplied;
        uint256 totalWithdrawn;

        for (uint256 i; i < _allocations.length; ++i) {
            MarketAllocation memory allocation = _allocations[i];

            // Update internal balance for market to include interest if any.
            _updateInternalBalanceForMarket(allocation.market);

            // in original SiloVault, we are not checking liquidity, so this reallocation will fail if not enough assets
            (uint256 supplyAssets, uint256 supplyShares) = SiloVaultActionsLib.supplyBalance(allocation.market);
            uint256 withdrawn = UtilsLib.zeroFloorSub(supplyAssets, allocation.assets);

            if (withdrawn > 0) {
                if (!config[allocation.market].enabled) revert ErrorsLib.MarketNotEnabled(allocation.market);

                // Guarantees that unknown frontrunning donations can be withdrawn, in order to disable a market.
                // However, setting `allocation.assets` to 0 does not guarantee successful fund reallocation if the
                // withdrawn assets would cause the following markets to exceed their supply caps during reallocation.
                uint256 shares;
                if (allocation.assets == 0) {
                    shares = supplyShares;
                    withdrawn = 0;
                }

                uint256 withdrawnAssets;
                uint256 withdrawnShares;
                address asset = asset();
                uint256 balanceBefore = SiloVaultActionsLib.ERC20BalanceOf(asset, address(this));

                if (shares != 0) {
                    withdrawnAssets = allocation.market.redeem(shares, address(this), address(this));
                    withdrawnShares = shares;
                } else {
                    withdrawnAssets = withdrawn;
                    withdrawnShares = allocation.market.withdraw(withdrawn, address(this), address(this));
                }

                // Ensure we received what was expected/reported on withdraw.
                _checkAfterWithdraw(asset, balanceBefore, withdrawnAssets);

                // Balances tracker can accumulate dust.
                // For example, if a user has deposited 100wei and withdrawn 99wei (because of rounding),
                // we will still have 1wei in balanceTracker[market]. But, this dust can be covered
                // by accrued interest over time.
                balanceTracker[allocation.market] = UtilsLib.zeroFloorSub(
                    balanceTracker[allocation.market],
                    withdrawnAssets
                );

                emit EventsLib.ReallocateWithdraw(_msgSender(), allocation.market, withdrawnAssets, withdrawnShares);

                totalWithdrawn += withdrawnAssets;
            } else {
                uint256 suppliedAssets = allocation.assets == type(uint256).max
                    ? UtilsLib.zeroFloorSub(totalWithdrawn, totalSupplied)
                    : UtilsLib.zeroFloorSub(allocation.assets, supplyAssets);

                if (suppliedAssets == 0) continue;

                uint256 supplyCap = config[allocation.market].cap;
                if (supplyCap == 0) revert ErrorsLib.UnauthorizedMarket(allocation.market);

                if (supplyAssets + suppliedAssets > supplyCap) revert ErrorsLib.SupplyCapExceeded(allocation.market);

                uint256 newBalance = balanceTracker[allocation.market] + suppliedAssets;

                if (newBalance > supplyCap) revert ErrorsLib.InternalSupplyCapExceeded(allocation.market);

                balanceTracker[allocation.market] = newBalance;

                // The market's loan asset is guaranteed to be the vault's asset because it has a non-zero supply cap.
                (
                    , uint256 suppliedShares
                ) = _marketSupply({_market: allocation.market, _assets: suppliedAssets, _revertOnFail: true});

                emit EventsLib.ReallocateSupply(_msgSender(), allocation.market, suppliedAssets, suppliedShares);

                totalSupplied += suppliedAssets;
            }
        }

        if (totalWithdrawn != totalSupplied) revert ErrorsLib.InconsistentReallocation();

        _nonReentrantOff();
    }

    /* REVOKE FUNCTIONS */

    /// @inheritdoc ISiloVaultBase
    function revokePendingTimelock() external virtual onlyGuardianRole {
        delete pendingTimelock;

        emit EventsLib.RevokePendingTimelock(_msgSender());
    }

    /// @inheritdoc ISiloVaultBase
    function revokePendingGuardian() external virtual onlyGuardianRole {
        delete pendingGuardian;

        emit EventsLib.RevokePendingGuardian(_msgSender());
    }

    /// @inheritdoc ISiloVaultBase
    function revokePendingCap(IERC4626 _market) external virtual onlyCuratorOrGuardianRole {
        delete pendingCap[_market];

        emit EventsLib.RevokePendingCap(_msgSender(), _market);
    }

    /// @inheritdoc ISiloVaultBase
    function revokePendingMarketRemoval(IERC4626 _market) external virtual onlyCuratorOrGuardianRole {
        delete config[_market].removableAt;

        emit EventsLib.RevokePendingMarketRemoval(_msgSender(), _market);
    }

    /* EXTERNAL */

    /// @inheritdoc ISiloVaultBase
    function supplyQueueLength() external view virtual returns (uint256) {
        return supplyQueue.length;
    }

    /// @inheritdoc ISiloVaultBase
    function withdrawQueueLength() external view virtual returns (uint256) {
        return withdrawQueue.length;
    }

    /// @inheritdoc ISiloVaultBase
    function acceptTimelock() external virtual afterTimelock(pendingTimelock.validAt) {
        _setTimelock(pendingTimelock.value);
    }

    /// @inheritdoc ISiloVaultBase
    function acceptGuardian() external virtual afterTimelock(pendingGuardian.validAt) {
        _setGuardian(pendingGuardian.value);
    }

    /// @inheritdoc ISiloVaultBase
    function acceptCap(IERC4626 _market)
        external
        virtual
        afterTimelock(pendingCap[_market].validAt)
    {
        _nonReentrantOn();

        // Safe to cast because pendingCap <= type(uint184).max.
        _setCap(_market, uint184(pendingCap[_market].value));

        _nonReentrantOff();
    }

    /// @inheritdoc ISiloVaultBase
    function claimRewards() public virtual {
        _nonReentrantOn();

        _updateLastTotalAssets(_accrueFee());
        _claimRewards();

        _nonReentrantOff();
    }

    /// @inheritdoc ISiloVaultBase
    function reentrancyGuardEntered() external view virtual returns (bool entered) {
        entered = _lock;
    }

    /* ERC4626 (PUBLIC) */

    /// @notice Decimals are the same as underlying asset. Decimal offset is not accounted for in decimals.
    /// SiloVault do not have an initial 1:1 shares-to-assets rate with underlying markets.
    /// @dev SiloVault is using decimal offset of 1e6. This means that depositing 1 asset results in 1,000,000 shares,
    /// although this is not a fixed ratio and will grow over time.
    ///
    /// Learn more about the offset here:
    /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/a7d38c7a3321e3832ca84f7ba1125dff9a91361e/contracts/token/ERC20/extensions/ERC4626.sol#L31
    ///
    /// The share-to-asset ratio may change over time due to interest accrual. As assets grow with interest
    /// but the number of shares remains constant, the ratio will adjust dynamically.
    ///
    /// To determine the current conversion rate, use the vault’s `convertToShares(1 asset)` method.
    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be higher than the actual max deposit due to duplicate markets in the supplyQueue.
    function maxDeposit(address) public view virtual override returns (uint256) {
        return SiloVaultActionsLib.maxDeposit(supplyQueue, config, balanceTracker);
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be higher than the actual max mint due to duplicate markets in the supplyQueue.
    function maxMint(address) public view virtual override returns (uint256) {
        uint256 suppliable = SiloVaultActionsLib.maxDeposit(supplyQueue, config, balanceTracker);

        return _convertToShares(suppliable, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be lower than the actual amount of assets that can be withdrawn by `owner` due to conversion
    /// roundings between shares and assets.
    function maxWithdraw(address _owner) public view virtual override returns (uint256 assets) {
        (assets,,) = _maxWithdraw(_owner);
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be lower than the actual amount of shares that can be redeemed by `owner` due to conversion
    /// roundings between shares and assets.
    function maxRedeem(address _owner) public view virtual override returns (uint256 shares) {
        (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) = _maxWithdraw(_owner);
        if (assets == 0) return 0;

        shares = _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, Math.Rounding.Floor);

        /*
        there might be a case where conversion from assets <=> shares is not returning same amounts eg:
        convert to shares ==> 1 * (1002 + 1e3) / (2 + 1) = 667.3
        convert to assets ==> 667 * (2 + 1) / (1002 + 1e3) = 0.9995
        so when user will use 667 withdrawal will fail, this is why we have to cross check:
        */
        if (_convertToAssetsWithTotals(shares, newTotalSupply, newTotalAssets, Math.Rounding.Floor) == 0) return 0;
    }

    /// @inheritdoc IERC20
    function transfer(address _to, uint256 _value) public virtual override(ERC20, IERC20) returns (bool success) {
        _nonReentrantOn();

        _updateLastTotalAssets(_accrueFee());

        success = ERC20.transfer(_to, _value);

        _nonReentrantOff();
    }

    /// @inheritdoc IERC20
    function transferFrom(address _from, address _to, uint256 _value)
        public
        virtual
        override(ERC20, IERC20)
        returns (bool success)
    {
        _nonReentrantOn();

        _updateLastTotalAssets(_accrueFee());

        success = ERC20.transferFrom(_from, _to, _value);

        _nonReentrantOff();
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public virtual override returns (uint256 shares) {
        _nonReentrantOn();

        uint256 newTotalAssets = _accrueFee();

        // Update `lastTotalAssets` to avoid an inconsistent state in a re-entrant context.
        // It is updated again in `_deposit`.
        lastTotalAssets = newTotalAssets;

        shares = _convertToSharesWithTotalsSafe(_assets, totalSupply(), newTotalAssets, Math.Rounding.Floor);

        _deposit(_msgSender(), _receiver, _assets, shares);

        _nonReentrantOff();
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) public virtual override returns (uint256 assets) {
        _nonReentrantOn();

        uint256 newTotalAssets = _accrueFee();

        // Update `lastTotalAssets` to avoid an inconsistent state in a re-entrant context.
        // It is updated again in `_deposit`.
        lastTotalAssets = newTotalAssets;

        assets = _convertToAssetsWithTotalsSafe(_shares, totalSupply(), newTotalAssets, Math.Rounding.Ceil);

        _deposit(_msgSender(), _receiver, assets, _shares);

        _nonReentrantOff();
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        _nonReentrantOn();

        uint256 newTotalAssets = _accrueFee();

        // Do not call expensive `maxWithdraw` and optimistically withdraw assets.

        shares = _convertToSharesWithTotalsSafe(_assets, totalSupply(), newTotalAssets, Math.Rounding.Ceil);

        // `newTotalAssets - assets` may be a little off from `totalAssets()`.
        _updateLastTotalAssets(UtilsLib.zeroFloorSub(newTotalAssets, _assets));

        _withdraw(_msgSender(), _receiver, _owner, _assets, shares);

        _nonReentrantOff();
    }

    /// @inheritdoc IERC4626
    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public virtual override returns (uint256 assets) {
        _nonReentrantOn();

        uint256 newTotalAssets = _accrueFee();

        // Do not call expensive `maxRedeem` and optimistically redeem shares.

        assets = _convertToAssetsWithTotalsSafe(_shares, totalSupply(), newTotalAssets, Math.Rounding.Floor);

        // `newTotalAssets - assets` may be a little off from `totalAssets()`.
        _updateLastTotalAssets(UtilsLib.zeroFloorSub(newTotalAssets, assets));

        _withdraw(_msgSender(), _receiver, _owner, assets, _shares);

        _nonReentrantOff();
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view virtual override returns (uint256 assets) {
        uint256 length = withdrawQueue.length;

        for (uint256 i; i < length; ++i) {
            IERC4626 market = withdrawQueue[i];
            assets += SiloVaultActionsLib.expectedSupplyAssets(market);
        }
    }

    /* ERC4626 (INTERNAL) */

    /// @inheritdoc ERC4626
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return DECIMALS_OFFSET;
    }

    /// @dev Returns the maximum amount of asset (`assets`) that the `owner` can withdraw from the vault, as well as the
    /// new vault's total supply (`newTotalSupply`) and total assets (`newTotalAssets`).
    function _maxWithdraw(address _owner)
        internal
        view
        virtual
        returns (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets)
    {
        uint256 feeShares;
        (feeShares, newTotalAssets) = _accruedFeeShares();
        newTotalSupply = totalSupply() + feeShares;

        assets = _convertToAssetsWithTotals(balanceOf(_owner), newTotalSupply, newTotalAssets, Math.Rounding.Floor);
        assets -= SiloVaultActionsLib.simulateWithdrawERC4626(assets, withdrawQueue);
    }

    /// @inheritdoc ERC4626
    /// @dev The accrual of performance fees is taken into account in the conversion.
    function _convertToShares(uint256 _assets, Math.Rounding _rounding)
        internal
        view
        virtual
        override
        returns (uint256 shares)
    {
        (uint256 feeShares, uint256 newTotalAssets) = _accruedFeeShares();

        shares = _convertToSharesWithTotals(_assets, totalSupply() + feeShares, newTotalAssets, _rounding);
    }

    /// @inheritdoc ERC4626
    /// @dev The accrual of performance fees is taken into account in the conversion.
    function _convertToAssets(uint256 _shares, Math.Rounding _rounding)
        internal
        view
        virtual
        override
        returns (uint256 assets)
    {
        (uint256 feeShares, uint256 newTotalAssets) = _accruedFeeShares();
        assets = _convertToAssetsWithTotals(_shares, totalSupply() + feeShares, newTotalAssets, _rounding);
    }

    /// @dev Returns the amount of shares that the vault would exchange for the amount of `assets` provided.
    /// @dev It assumes that the arguments `newTotalSupply` and `newTotalAssets` are up to date.
    function _convertToSharesWithTotals(
        uint256 _assets,
        uint256 _newTotalSupply,
        uint256 _newTotalAssets,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256 shares) {
        shares = _assets.mulDiv(_newTotalSupply + 10 ** _decimalsOffset(), _newTotalAssets + 1, _rounding);
    }

    /// @dev Returns the amount of shares that the vault would exchange for the amount of `assets` provided.
    /// @dev It assumes that the arguments `newTotalSupply` and `newTotalAssets` are up to date.
    /// @dev Reverts if the result is zero.
    function _convertToSharesWithTotalsSafe(
        uint256 _assets,
        uint256 _newTotalSupply,
        uint256 _newTotalAssets,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256 shares) {
        shares = _convertToSharesWithTotals(_assets, _newTotalSupply, _newTotalAssets, _rounding);
        require(shares != 0, ErrorsLib.ZeroShares());
    }

    /// @dev Returns the amount of assets that the vault would exchange for the amount of `shares` provided.
    /// @dev It assumes that the arguments `newTotalSupply` and `newTotalAssets` are up to date.
    function _convertToAssetsWithTotals(
        uint256 _shares,
        uint256 _newTotalSupply,
        uint256 _newTotalAssets,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256 assets) {
        assets = _shares.mulDiv(_newTotalAssets + 1, _newTotalSupply + 10 ** _decimalsOffset(), _rounding);
    }

    /// @dev Returns the amount of assets that the vault would exchange for the amount of `shares` provided.
    /// @dev It assumes that the arguments `newTotalSupply` and `newTotalAssets` are up to date.
    /// @dev Reverts if the result is zero.
    function _convertToAssetsWithTotalsSafe(
        uint256 _shares,
        uint256 _newTotalSupply,
        uint256 _newTotalAssets,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256 assets) {
        assets = _convertToAssetsWithTotals(_shares, _newTotalSupply, _newTotalAssets, _rounding);
        require(assets != 0, ErrorsLib.ZeroAssets());
    }

    /// @inheritdoc ERC4626
    /// @dev Used in mint or deposit to deposit the underlying asset to ERC4626 vaults.
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override {
        if (_shares == 0) revert ErrorsLib.InputZeroShares();

        super._deposit(_caller, _receiver, _assets, _shares);

        _supplyERC4626(_assets);

        // `lastTotalAssets + assets` may be a little off from `totalAssets()`.
        _updateLastTotalAssets(lastTotalAssets + _assets);
    }

    /// @inheritdoc ERC4626
    /// @dev Used in redeem or withdraw to withdraw the underlying asset from ERC4626 markets.
    /// @dev Depending on 3 cases, reverts when withdrawing "too much" with:
    /// 1. NotEnoughLiquidity when withdrawing more than available liquidity.
    /// 2. ERC20InsufficientAllowance when withdrawing more than `caller`'s allowance.
    /// 3. ERC20InsufficientBalance when withdrawing more than `owner`'s balance.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares)
        internal
        virtual
        override
    {
        _withdrawERC4626(_assets);
        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /* INTERNAL */

    /// @dev Updates the internal balance for the market.
    function _updateInternalBalanceForMarket(IERC4626 _market)
        internal
        virtual
        returns (uint256 marketBalance)
    {
        marketBalance = SiloVaultActionsLib.expectedSupplyAssets(_market);

        if (marketBalance != 0 && marketBalance > balanceTracker[_market]) {
            balanceTracker[_market] = marketBalance;
        }
    }

    /// @dev Reverts if `newTimelock` is not within the bounds.
    function _checkTimelockBounds(uint256 _newTimelock) internal pure virtual {
        if (_newTimelock > ConstantsLib.MAX_TIMELOCK) revert ErrorsLib.AboveMaxTimelock();
        if (_newTimelock < ConstantsLib.MIN_TIMELOCK) revert ErrorsLib.BelowMinTimelock();
    }

    /// @dev Sets `timelock` to `newTimelock`.
    function _setTimelock(uint256 _newTimelock) internal virtual {
        timelock = _newTimelock;

        emit EventsLib.SetTimelock(_msgSender(), _newTimelock);

        delete pendingTimelock;
    }

    /// @dev Sets `guardian` to `newGuardian`.
    function _setGuardian(address _newGuardian) internal virtual {
        guardian = _newGuardian;

        emit EventsLib.SetGuardian(_msgSender(), _newGuardian);

        delete pendingGuardian;
    }

    /// @dev Sets the cap of the market.
    function _setCap(IERC4626 _market, uint184 _supplyCap) internal virtual {
        bool updateTotalAssets = SiloVaultActionsLib.setCap(
            _market,
            _supplyCap,
            asset(),
            config,
            pendingCap,
            withdrawQueue
        );

        if (updateTotalAssets) {
            _updateLastTotalAssets(lastTotalAssets + SiloVaultActionsLib.expectedSupplyAssets(_market));
        }
    }

    /* LIQUIDITY ALLOCATION */

    /// @dev Supplies `assets` to ERC4626 vaults.
    function _supplyERC4626(uint256 _assets) internal virtual {
        uint256 length = supplyQueue.length;

        for (uint256 i; i < length; ++i) {
            IERC4626 market = supplyQueue[i];

            uint256 supplyCap = config[market].cap;
            if (supplyCap == 0) continue;

            // Update internal balance for market to include interest if any.
            // `supplyAssets` needs to be rounded up for `toSupply` to be rounded down.
            uint256 supplyAssets = _updateInternalBalanceForMarket(market);

            // Check if we are not reaching the supply cap. If so, supply up to the cap.
            uint256 toSupply = UtilsLib.min(UtilsLib.zeroFloorSub(supplyCap, supplyAssets), _assets);

            if (toSupply != 0) {
                // As `_updateInternalBalanceForMarket` reads the balance directly from the market,
                // we have additional check to ensure that the market did not report wrong supply.
                uint256 internalBalanceTracker = balanceTracker[market];

                // As `internalBalanceTracker` is always >= `supplyAssets`
                // to deposit up to the internal balance we need to recalculate `toSupply`.
                toSupply = UtilsLib.min(UtilsLib.zeroFloorSub(supplyCap, internalBalanceTracker), toSupply);

                if (toSupply != 0) {
                    // If caps are not reached, cap the amount to supply to the max deposit amount of the market.
                    toSupply = UtilsLib.min(market.maxDeposit(address(this)), toSupply);
                    // Skip the market if max deposit is 0.
                    if (toSupply == 0) continue;

                    // `_marketSupply` is using try/catch to skip markets that revert.
                    (bool success,) = _marketSupply({_market: market, _assets: toSupply, _revertOnFail: false});

                    if (success) {
                        _assets -= toSupply;
                        balanceTracker[market] = internalBalanceTracker + toSupply;
                    }
                }
            }

            if (_assets == 0) return;
        }

        if (_assets != 0) revert ErrorsLib.AllCapsReached();
    }

    /// @dev Withdraws `assets` from ERC4626 vaults.
    function _withdrawERC4626(uint256 _assets) internal virtual {
        uint256 length = withdrawQueue.length;

        for (uint256 i; i < length; ++i) {
            IERC4626 market = withdrawQueue[i];

            // Update internal balance for market to include interest if any.
            _updateInternalBalanceForMarket(market);

            // original implementation were using `_accruedSupplyBalance` which does not care about liquidity
            // now, liquidity is considered by using `maxWithdraw`
            uint256 toWithdraw = UtilsLib.min(market.maxWithdraw(address(this)), _assets);

            if (toWithdraw > 0) {
                address asset = asset();
                uint256 balanceBefore = SiloVaultActionsLib.ERC20BalanceOf(asset, address(this));
                // Using try/catch to skip markets that revert.
                try market.withdraw(toWithdraw, address(this), address(this)) {
                    _assets -= toWithdraw;

                    // Ensure we received what was expected on withdraw.
                    _checkAfterWithdraw(asset, balanceBefore, toWithdraw);

                    // Balances tracker can accumulate dust.
                    // For example, if a user has deposited 100wei and withdrawn 99wei (because of rounding),
                    // we will still have 1wei in balanceTracker[market]. But, this dust can be covered
                    // by accrued interest over time.
                    balanceTracker[market] = UtilsLib.zeroFloorSub(balanceTracker[market], toWithdraw);
                } catch {
                }
            }

            if (_assets == 0) return;
        }

        if (_assets != 0) revert ErrorsLib.NotEnoughLiquidity();
    }

    /* FEE MANAGEMENT */

    /// @dev Updates `lastTotalAssets` to `updatedTotalAssets`.
    function _updateLastTotalAssets(uint256 _updatedTotalAssets) internal virtual {
        lastTotalAssets = _updatedTotalAssets;
        emit EventsLib.UpdateLastTotalAssets(_updatedTotalAssets);
    }

    /// @dev Accrues the fee and mints the fee shares to the fee recipient.
    /// @return newTotalAssets The vaults total assets after accruing the interest.
    function _accrueFee() internal virtual returns (uint256 newTotalAssets) {
        uint256 feeShares;
        (feeShares, newTotalAssets) = _accruedFeeShares();

        if (feeShares != 0) _mint(feeRecipient, feeShares);

        emit EventsLib.AccrueInterest(newTotalAssets, feeShares);
    }

    /// @dev Computes and returns the fee shares (`feeShares`) to mint and the new vault's total assets
    /// (`newTotalAssets`).
    function _accruedFeeShares() internal view virtual returns (uint256 feeShares, uint256 newTotalAssets) {
        newTotalAssets = totalAssets();

        uint256 totalInterest = UtilsLib.zeroFloorSub(newTotalAssets, lastTotalAssets);
        if (totalInterest != 0 && fee != 0) {
            // It is acknowledged that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
            uint256 feeAssets = totalInterest.mulDiv(fee, WAD);

            // The fee assets is subtracted from the total assets in this calculation to compensate for the fact
            // that total assets is already increased by the total interest (including the fee assets).
            feeShares =
                _convertToSharesWithTotals(feeAssets, totalSupply(), newTotalAssets - feeAssets, Math.Rounding.Floor);
        }
    }

    function _update(address _from, address _to, uint256 _value) internal virtual override {
        // on deposit, claim must be first action, new user should not get reward

        // on withdraw, claim must be first action, user that is leaving should get rewards
        // immediate deposit-withdraw operation will not abused it, because before deposit all rewards will be
        // claimed, so on withdraw on the same block no additional rewards will be generated.

        // transfer shares is basically withdraw->deposit, so claiming rewards should be done before any state changes

        _claimRewards();

        super._update(_from, _to, _value);

        if (_value == 0) return;

        _afterTokenTransfer(_from, _to, _value);
    }

    function _afterTokenTransfer(address _from, address _to, uint256 _value) internal virtual {
        address[] memory receivers = INCENTIVES_MODULE.getNotificationReceivers();

        if (receivers.length == 0) return;

        uint256 total = totalSupply();
        uint256 senderBalance = _from == address(0) ? 0 : balanceOf(_from);
        uint256 recipientBalance = _to == address(0) ? 0 : balanceOf(_to);

        for (uint256 i; i < receivers.length; i++) {
            INotificationReceiver(receivers[i]).afterTokenTransfer({
                _sender: _from,
                _senderBalance: senderBalance,
                _recipient: _to,
                _recipientBalance: recipientBalance,
                _totalSupply: total,
                _amount: _value
            });
        }
    }

    function _claimRewards() internal virtual {
        address[] memory logics = INCENTIVES_MODULE.getAllIncentivesClaimingLogics();
        bytes memory data = abi.encodeWithSelector(IIncentivesClaimingLogic.claimRewardsAndDistribute.selector);

        for (uint256 i; i < logics.length; i++) {
            (bool success,) = logics[i].delegatecall(data);
            if (!success) revert ErrorsLib.ClaimRewardsFailed();
        }
    }

    function _nonReentrantOn() internal {
        require(!_lock, ErrorsLib.ReentrancyError());
        _lock = true;
    }

    function _nonReentrantOff() internal {
        _lock = false;
    }

    function _marketSupply(IERC4626 _market, uint256 _assets, bool _revertOnFail)
        internal
        returns (bool success, uint256 shares)
    {
        IERC20 asset = IERC20(asset());

        if (!_revertOnFail && _market.previewDeposit(_assets) == 0) {
            return (false, 0);
        }

        // Approving the exact amount because we don't want `transferFrom` to bypass `balanceTracker`.
        asset.forceApprove({spender: address(_market), value: _assets});

        try _market.deposit(_assets, address(this)) returns (uint256 gotShares) {
            require(gotShares != 0, ErrorsLib.ZeroShares());

            shares = gotShares;
            success = true;

            _priceManipulationCheck(_market, shares, _assets);
        } catch (bytes memory data) {
            if (_revertOnFail) ErrorsLib.revertBytes(data);
        }

        // Reset approval regardless of the deposit success or failure.
        // Setting to 1 wei to support tokens that revert when approving 0
        asset.forceApprove({spender: address(_market), value: 1});
    }

    function _priceManipulationCheck(IERC4626 _market, uint256 _shares, uint256 _assets) internal view {
        uint256 previewAssets = SiloVaultActionsLib.previewRedeem(_market, _shares);
        if (previewAssets >= _assets) return;

        uint256 threshold = arbitraryLossThreshold[_market].threshold;
        threshold = threshold == 0 ? DEFAULT_LOST_THRESHOLD : threshold;

        unchecked {
            uint256 loss = _assets - previewAssets;
            require(loss < threshold, ErrorsLib.AssetLoss(loss));
        }
    }

    /// @dev Check that ensures that we received what was expected/reported on withdraw.
    /// @param _asset The asset that was withdrawn.
    /// @param _balanceBefore The balance of the asset before the withdrawal.
    /// @param _withdrawnAssets The amount of assets that were withdrawn.
    function _checkAfterWithdraw(address _asset, uint256 _balanceBefore, uint256 _withdrawnAssets) internal view {
        uint256 balanceAfter = SiloVaultActionsLib.ERC20BalanceOf(_asset, address(this));

        if (_balanceBefore + _withdrawnAssets != balanceAfter) revert ErrorsLib.FailedToWithdraw();
    }
}
