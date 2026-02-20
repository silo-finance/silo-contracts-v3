// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/// @title Wrapped USD+ / USD adapter
/// @notice WusdPlusUsdAdapter is the price adapter for wUSD+ token. Price calculations depends
/// on the price of USD+.
contract WusdPlusUsdAdapter is AggregatorV3Interface {
    /// @dev Sample amount for wUSD+ / USD+ conversion rate calculations.
    int256 public constant SAMPLE_AMOUNT = 10 ** 18;

    /// @dev USD+ / USD aggregator decimals
    uint8 public immutable USD_PLUS_USD_AGGREGATOR_DECIMALS;

    /// @dev WUSD+ token address
    address public immutable WUSD_PLUS;

    /// @dev USD+ is an underlying asset of wUSD+
    address public immutable UNDERLYING; // solhint-disable-line var-name-mixedcase

    /// @dev USD+ / USD aggregator address
    address public immutable USD_PLUS_USD_AGGREGATOR;

    /// @param _wusdPlus WUSD+ token address
    /// @param _usdPlusUsdAggregator ChainlinkUSD+ / USD aggregator address
    constructor(address _wusdPlus, address _usdPlusUsdAggregator) {
        WUSD_PLUS = _wusdPlus;
        UNDERLYING = IERC4626(_wusdPlus).asset();
        USD_PLUS_USD_AGGREGATOR = _usdPlusUsdAggregator;
        USD_PLUS_USD_AGGREGATOR_DECIMALS = AggregatorV3Interface(_usdPlusUsdAggregator).decimals();
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
        // Get SAMPLE_AMOUNT of wUSD+ in USD+.
        // Safe: SAMPLE_AMOUNT is uint80 max, which always fits into uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 sampleConversionRate = SafeCast.toInt256(IERC4626(WUSD_PLUS).convertToAssets(uint256(SAMPLE_AMOUNT)));

        int256 usdPlusPrice;

        // Get USD+ price from USD+ / USD aggregator
        (
            roundId,
            usdPlusPrice,
            startedAt,
            updatedAt,
            answeredInRound
        ) = AggregatorV3Interface(USD_PLUS_USD_AGGREGATOR).latestRoundData();

        // Get USD+ price and multiply it by USD+ per wUSD+ ratio
        answer = usdPlusPrice * sampleConversionRate;
        unchecked { answer /= SAMPLE_AMOUNT; }
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external view virtual returns (uint8) {
        return USD_PLUS_USD_AGGREGATOR_DECIMALS;
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external pure virtual returns (string memory) {
        return "WUSD+ / USD";
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80)
        external
        pure
        virtual
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        revert("not implemented");
    }
}
