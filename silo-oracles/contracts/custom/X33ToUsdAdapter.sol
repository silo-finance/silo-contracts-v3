// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title x33 / USD adapter
/// @notice This adapter multiplies the x33.convertToAssets() go get the rate between x33 and xShadow. To get the
/// rate between xShadow and Shadow 50% multiplier is used (slashing penalty in Shadow is constant). AggregatorV3 feed
/// provided in constructor is used as Shadow / USD price source. 
contract X33ToUsdAdapter is AggregatorV3Interface {
    /// @dev 50% slashing penalty to redeem xShadow for Shadow. 
    int256 public constant SLASHING_PENALTY_DIVIDER = 2;

    /// @dev sample amount for x33.convertToAssets(). 
    uint256 public constant SHARES_QUOTE_SAMPLE = 10 ** 18;

    /// @dev x33 vault address to do x33.convertToAssets(). 
    IERC4626 public constant X33 = IERC4626(0x3333111A391cC08fa51353E9195526A70b333333);

    /// @dev Shadow / USD feed. 
    AggregatorV3Interface public immutable SHADOW_USD_FEED; // solhint-disable-line var-name-mixedcase

    error InvalidShadowUsdFeed();
    error NotImplemented();

    constructor(AggregatorV3Interface _shadowUsdFeed) {
        require(address(_shadowUsdFeed) != address(0), InvalidShadowUsdFeed());

        (, int256 answer,, uint256 updatedAt,) = _shadowUsdFeed.latestRoundData();
        require(answer > 0 && block.timestamp - updatedAt < 24 hours, InvalidShadowUsdFeed());

        SHADOW_USD_FEED = _shadowUsdFeed;
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        virtual
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = SHADOW_USD_FEED.latestRoundData();

        // price := x33 --(rate)--> xShadow --(50% penalty)--> Shadow --(underlying feed)--> USD
        // price := (X33.convertToAssets(SHARES_QUOTE_SAMPLE) / int256(SHARES_QUOTE_SAMPLE)) / 2 * answer

        // Safe: SHARES_QUOTE_SAMPLE is a small positive constant, so int256 conversion is always in range.
        // forge-lint: disable-next-line(unsafe-typecast)
        answer = (
            answer * SafeCast.toInt256(X33.convertToAssets(SHARES_QUOTE_SAMPLE)) / int256(SHARES_QUOTE_SAMPLE)
        ) / SLASHING_PENALTY_DIVIDER;
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external view virtual returns (uint8) {
        return SHADOW_USD_FEED.decimals();
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external pure virtual returns (string memory) {
        return "x33 / USD adapter";
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80) external pure virtual returns (uint80, int256, uint256, uint256, uint80) {
        revert NotImplemented();
    }
}
