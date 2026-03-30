// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ISupraSValueFeed {
    /// @notice Supra push oracle payload returned by `getSvalue`.
    /// @dev Fields reflect Supra S-Value feed response shape.
    /// @param round Feed round identifier returned by Supra.
    /// @param decimals Number of decimals used by `price`.
    /// @param time Unix timestamp (seconds) when this value was published/updated by Supra feed.
    /// @param price Raw price value for requested pair index, scaled by `decimals`.
    struct PriceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    /// @notice Returns latest S-Value data for pair index.
    /// @param _pairIndex Pair identifier from Supra data feed index.
    /// @return feed Latest price payload for `_pairIndex`.
    function getSvalue(uint256 _pairIndex) external view returns (PriceFeed memory feed);
}
