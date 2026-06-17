// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

/// @title IDualOracle
/// @notice Interface for Silo's Dual Oracle — a wrapper around any ISiloOracle primary source
///         that adds two governance-controlled safety mechanisms:
///
///         1. **Pause mode** (immediate) — reverts all price requests; highest priority.
///         2. **Manual price override** (timelock-guarded activation, immediate updates) —
///            replaces the primary oracle price with an admin-set value constrained by
///            immutable lower / upper bounds.
///
///         Priority order (highest → lowest):
///           Paused > Override active > Primary oracle
///
///         Access control:
///           DEFAULT_ADMIN_ROLE (bytes32(0)) — full control: pause, unpause, setManualPrice, manage roles
///           PRICE_SETTER_ROLE               — restricted: setManualPrice only
///
///         Pause / unpause events and the `paused()` view are inherited from OZ PausableUpgradeable.
interface IDualOracle is ISiloOracle, IVersioned, IAccessControl {
    /// @notice Role identifier for addresses that may call setManualPrice
    // solhint-disable-next-line func-name-mixedcase
    function PRICE_SETTER_ROLE() external view returns (bytes32);
    /// @notice Emitted whenever the manual price or override activation timestamp is updated.
    /// @param price   The new manual price (18-decimal quote units per base unit); zero means override disabled
    /// @param validAt Timestamp from which the override becomes active; zero means override disabled
    event ManualPriceUpdated(uint256 price, uint64 validAt);

    error ZeroOracle();
    error ZeroOwner();
    /// @notice lowerPriceBound must be > 0 and < upperPriceBound
    error LowerBoundMustBeGreaterThanZero();
    error InvalidBounds();
    error BaseTokenDecimalsMustBeGreaterThanZero();
    /// @notice Submitted price equals the currently stored manual price
    error PriceNotChanged();
    /// @notice Submitted price is below the immutable lower bound
    error PriceBelowLowerBound();
    /// @notice Submitted price is above the immutable upper bound
    error PriceAboveUpperBound();
    /// @notice _baseToken passed to quote() or beforeQuote() is not the token this oracle prices
    error AssetNotSupported();
    /// @notice Computed quote rounds down to zero for a non-zero _baseAmount
    error ZeroQuote();

    /// @notice Immediately pauses the oracle.
    ///         While paused, all quote() calls revert via OZ EnforcedPause.
    ///         Pause has highest priority and supersedes override mode.
    ///         Only callable by the owner.
    function pause() external;

    /// @notice Removes the pause, resuming normal price responses.
    ///         Only callable by the owner.
    function unpause() external;

    /// @notice Sets the manual price and manages override activation.
    ///
    ///         Behaviour by price value:
    ///         - _price == 0  → clears manualPrice and overrideValidAt, disables override immediately
    ///                          (emits ManualPriceUpdated(0, 0))
    ///         - _price != 0  → validates bounds, stores price; if override not yet active, starts the timelock
    ///                          (emits ManualPriceUpdated(_price, overrideValidAt))
    ///
    ///         Price updates do NOT restart the timelock once the override is active.
    ///         Only callable by the owner.
    ///
    /// @param _price Manual price in 18-decimal quote units per base unit.
    ///               Must satisfy lowerPriceBound <= _price <= upperPriceBound (or be zero to disable).
    function setManualPrice(uint256 _price) external;

    /// @notice The immutable primary price source wrapped by this oracle
    function oracle() external view returns (ISiloOracle);

    /// @notice The token in which prices are denominated (forwarded from primary oracle)
    function quoteToken() external view returns (address);

    /// @notice The token being priced (forwarded from primary oracle)
    function baseToken() external view returns (address);

    /// @notice Native decimals of the base token
    function baseTokenDecimals() external view returns (uint256);

    /// @notice Timelock duration in seconds required between setManualPrice and override becoming active
    function timelock() external view returns (uint256);

    /// @notice Minimum manual price accepted by setManualPrice (inclusive, 18-decimal quote units)
    function lowerPriceBound() external view returns (uint256);

    /// @notice Maximum manual price accepted by setManualPrice (inclusive, 18-decimal quote units)
    function upperPriceBound() external view returns (uint256);

    /// @notice The stored manual price in 18-decimal quote units per base unit.
    ///         Zero when override is not in use.
    function manualPrice() external view returns (uint256);

    /// @notice Unix timestamp at which the pending/active override becomes (or became) valid.
    ///         Zero means no override is pending or active.
    function overrideValidAt() external view returns (uint64);

    /// @notice Returns true when manualPrice is non-zero and the activation timelock has elapsed.
    ///         This is the condition under which quote() returns the manual price.
    function isOverrideActive() external view returns (bool);
}
