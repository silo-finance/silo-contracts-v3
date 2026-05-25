// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/// @title IDualOracle
/// @notice Dual-oracle-specific additions on top of ChainlinkV3Oracle:
///         pause mode and a bounded manual price override.
///         The full Chainlink oracle interface is provided by IChainlinkV3Oracle.
interface IDualOracle {
    // ─── Events ──────────────────────────────────────────────────────────────

    event OverrideEnabled(uint64 validAt);
    event OverrideDisabled();
    event ManualPriceSet(uint256 price);
    error PriceNotChanged();

    // ─── Errors ──────────────────────────────────────────────────────────────

    error PriceBelowLowerBound();
    error PriceAboveUpperBound();

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Sets the manual price while override mode is active.
    ///         Price must satisfy LOWER_BOUND <= _price <= UPPER_BOUND (raw feed units).
    ///         Can be called repeatedly without a new timelock.
    /// @param _price Manual price in raw feed units (same decimals as the primary aggregator)
    function setManualPrice(uint256 _price) external;

    // ─── View ─────────────────────────────────────────────────────────────────

    // NOTE: paused() is inherited from OZ PausableUpgradeable

    /// @notice Whether manual override mode is currently active
    function overrideActive() external view returns (bool);

    /// @notice The current manual price in raw feed units (meaningful only when override is active)
    function manualPrice() external view returns (uint256);

    /// @notice Timestamp at which the pending override activation becomes valid (0 if none pending)
    function overrideValidAt() external view returns (uint64);
}
