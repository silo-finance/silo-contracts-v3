// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

struct MarketConfig {
    /// @notice The maximum amount of assets that can be allocated to the market.
    uint184 cap;
    /// @notice Whether the market is in the withdraw queue.
    bool enabled;
    /// @notice The timestamp at which the market can be instantly removed from the withdraw queue.
    uint64 removableAt;
}

struct PendingUint192 {
    /// @notice The pending value to set.
    uint192 value;
    /// @notice The timestamp at which the pending value becomes valid.
    uint64 validAt;
}

struct PendingAddress {
    /// @notice The pending value to set.
    address value;
    /// @notice The timestamp at which the pending value becomes valid.
    uint64 validAt;
}

struct ArbitraryLossThreshold {
    uint256 threshold;
}

/// @title PendingLib
/// @dev Forked with gratitude from Morpho Labs.
/// @author Silo Labs
/// @custom:contact security@silo.finance
/// @notice Library to manage pending values and their validity timestamp.
library PendingLib {
    /// @dev Updates `_pending`'s value to `_newValue` and its corresponding `validAt` timestamp.
    /// @dev Assumes `timelock` <= `MAX_TIMELOCK`.
    function update(PendingUint192 storage _pending, uint184 _newValue, uint256 _timelock) internal {
        _pending.value = _newValue;
        // Safe "unchecked" cast because timelock <= MAX_TIMELOCK.
        // forge-lint: disable-next-line(unsafe-typecast)
        _pending.validAt = uint64(block.timestamp + _timelock);
    }

    /// @dev Updates `_pending`'s value to `_newValue` and its corresponding `validAt` timestamp.
    /// @dev Assumes `timelock` <= `MAX_TIMELOCK`.
    function update(PendingAddress storage _pending, address _newValue, uint256 _timelock) internal {
        _pending.value = _newValue;
        // Safe "unchecked" cast because timelock <= MAX_TIMELOCK.
        // forge-lint: disable-next-line(unsafe-typecast)
        _pending.validAt = uint64(block.timestamp + _timelock);
    }
}
