// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AccessControlEnumerableUpgradeable} from
    "openzeppelin5-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin5-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {Aggregator} from "../_common/Aggregator.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

/// @title DualOracle
/// @notice Wraps any ISiloOracle primary source and adds two governance-controlled
///         safety mechanisms: pause mode and a bounded manual price override.
///
///         Price resolution priority (highest → lowest):
///           1. Paused          → all quote() calls revert (OZ EnforcedPause)
///           2. Override active → returns the admin-set manual price
///           3. Normal          → delegates to the primary oracle
///
///         Override activation is timelock-guarded: calling setManualPrice() with a non-zero
///         value starts the countdown. Once elapsed, isOverrideActive() returns true and
///         quote() serves the manual price. Setting price to zero disables override immediately.
///         Pause / unpause are always immediate and have highest priority.
///
///         Access control:
///           DEFAULT_ADMIN_ROLE — full control: pause, unpause, setManualPrice, manage roles
///           PRICE_SETTER_ROLE  — restricted: setManualPrice only; granted/revoked by admin
///
/// @dev Deployed as a minimal proxy clone via DualOracleFactory.
///      Do not call initialize() directly — use the factory.
contract DualOracle is IDualOracle, Aggregator, AccessControlEnumerableUpgradeable, PausableUpgradeable {

    bytes32 public constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");

    /// @notice The immutable primary price source wrapped by this oracle
    ISiloOracle public oracle;

    /// @notice The token in which prices are denominated (forwarded from primary oracle)
    address public quoteToken;

    /// @notice Timelock duration in seconds required between setManualPrice and override becoming active
    uint256 public timelock;

    /// @notice Minimum manual price accepted by setManualPrice (inclusive, 18-decimal quote units)
    uint256 public lowerPriceBound;

    /// @notice Maximum manual price accepted by setManualPrice (inclusive, 18-decimal quote units)
    uint256 public upperPriceBound;

    /// @notice The stored manual price in 18-decimal quote units per base unit.
    ///         Zero when override is not in use.
    uint256 public manualPrice;

    /// @notice Unix timestamp at which the pending/active override becomes (or became) valid.
    ///         Zero means no override is pending or active.
    uint64 public overrideValidAt;

    /// @notice Native decimals of the base token
    uint256 public baseTokenDecimals;

    /// @dev Storage for the base token address; exposed via baseToken()
    address internal _baseTokenInternal;

    /// @notice Restricts access to DEFAULT_ADMIN_ROLE or PRICE_SETTER_ROLE.
    modifier onlyAdminOrPriceSetter() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(PRICE_SETTER_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, PRICE_SETTER_ROLE);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the cloned oracle instance.
    ///         Do not call this directly — use DualOracleFactory.
    /// @param _oracle      Primary price source; must be a valid ISiloOracle
    /// @param _owner       Address granted DEFAULT_ADMIN_ROLE (full control)
    /// @param _priceSetter Address granted PRICE_SETTER_ROLE; may be address(0) to skip
    /// @param _timelock        Override-activation timelock in seconds
    /// @param _lowerPriceBound Minimum accepted manual price (18-decimal quote units); must be > 0
    /// @param _upperPriceBound Maximum accepted manual price (18-decimal quote units); must be > _lowerPriceBound
    function initialize(
        ISiloOracle _oracle,
        address _owner,
        address _priceSetter,
        uint32 _timelock,
        uint256 _lowerPriceBound,
        uint256 _upperPriceBound
    ) external initializer {
        require(address(_oracle) != address(0), ZeroOracle());
        require(_owner != address(0), ZeroOwner());
        require(_lowerPriceBound > 0, LowerBoundMustBeGreaterThanZero());
        require(_lowerPriceBound < _upperPriceBound, InvalidBounds());

        __AccessControlEnumerable_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        if (_priceSetter != address(0)) _grantRole(PRICE_SETTER_ROLE, _priceSetter);

        oracle = _oracle;
        timelock = _timelock;
        _baseTokenInternal = Aggregator(address(_oracle)).baseToken();
        baseTokenDecimals = TokenHelper.assertAndGetDecimals(_baseTokenInternal);
        quoteToken = _oracle.quoteToken();
        lowerPriceBound = _lowerPriceBound;
        upperPriceBound = _upperPriceBound;

        require(baseTokenDecimals != 0, BaseTokenDecimalsMustBeGreaterThanZero());
    }

    /// @notice Forwards beforeQuote to the primary oracle when override is not active.
    ///         Skipped when override is active so a broken primary cannot block the override.
    /// @inheritdoc ISiloOracle
    function beforeQuote(address _baseToken) external virtual override whenNotPaused {
        require(_baseToken == _baseTokenInternal, AssetNotSupported());
        if (!isOverrideActive()) oracle.beforeQuote(_baseToken);
    }

    /// @notice Immediately pauses the oracle. All quote() calls revert while paused.
    ///         Pause has highest priority and supersedes override mode.
    ///         Only callable by DEFAULT_ADMIN_ROLE.
    /// @dev Delegates to OZ _pause(); emits Paused(msg.sender).
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Removes the pause, resuming normal price responses.
    ///         Only callable by DEFAULT_ADMIN_ROLE.
    /// @dev Delegates to OZ _unpause(); emits Unpaused(msg.sender).
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IDualOracle
    function setManualPrice(uint256 _price) external onlyAdminOrPriceSetter {
        require(_price != manualPrice, PriceNotChanged());

        if (_price == 0) {
            // allow setting zero price to disable override mode without a new timelock
            manualPrice = 0;
            overrideValidAt = 0;
        } else {
            require(_price >= lowerPriceBound, PriceBelowLowerBound());
            require(_price <= upperPriceBound, PriceAboveUpperBound());

            manualPrice = _price;

            // start the timelock only on the first price set; subsequent updates keep the original validAt
            if (overrideValidAt == 0) overrideValidAt = SafeCast.toUint64(block.timestamp + timelock);
        }

        emit ManualPriceUpdated(manualPrice, overrideValidAt);
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "DualOracle 4.23.0";
    }

    /// @inheritdoc IDualOracle
    function baseToken() public view override(Aggregator, IDualOracle) returns (address) {
        return _baseTokenInternal;
    }

    /// @notice Returns true when manualPrice is non-zero and the activation timelock has elapsed.
    ///         This is the condition under which quote() returns the manual price instead of
    ///         delegating to the primary oracle.
    function isOverrideActive() public view returns (bool) {
        uint64 validAt = overrideValidAt;
        return validAt != 0 && validAt <= block.timestamp;
    }

    /// @notice Returns the price of _baseAmount of _baseToken denominated in quoteToken.
    ///         Reverts when paused or when _baseToken is not supported.
    ///         Returns the scaled manual price when override is active, otherwise delegates to the primary oracle.
    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        whenNotPaused
        returns (uint256 quoteAmount)
    {
        require(_baseToken == _baseTokenInternal, AssetNotSupported());

        quoteAmount = isOverrideActive()
            ? Math.mulDiv(_baseAmount, manualPrice, 10 ** baseTokenDecimals)
            : oracle.quote(_baseAmount, _baseToken);

        require(quoteAmount != 0, ZeroQuote());
    }
}
