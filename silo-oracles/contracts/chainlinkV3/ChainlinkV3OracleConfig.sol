// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {IChainlinkV3Oracle} from "../interfaces/IChainlinkV3Oracle.sol";
import {Layer1OracleConfig} from "../_common/Layer1OracleConfig.sol";

contract ChainlinkV3OracleConfig is Layer1OracleConfig {
    /// @dev Chainlink aggregator
    AggregatorV3Interface internal immutable _AGGREGATOR; // solhint-disable-line var-name-mixedcase

    /// @dev secondary Chainlink aggregator to convert price to quote
    AggregatorV3Interface internal immutable _SECONDARY_AGGREGATOR; // solhint-disable-line var-name-mixedcase

    /// @dev Threshold used to determine if the price returned by the _SECONDARY_AGGREGATOR is valid
    uint256 internal immutable _SECONDARY_HEARTBEAT; // solhint-disable-line var-name-mixedcase

    /// @dev this can be set to true to convert primary price into price denominated in quote
    /// assuming that both AGGREGATORS providing price in the same token
    bool internal immutable _CONVERT_TO_QUOTE; // solhint-disable-line var-name-mixedcase

    /// @dev If TRUE price will be 1/price
    bool internal immutable _INVERT_SECONDARY_PRICE; // solhint-disable-line var-name-mixedcase

    /// @dev all verification should be done by factory
    constructor(IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory _config)
        Layer1OracleConfig(
            _config.baseToken,
            _config.quoteToken,
            _config.primaryHeartbeat,
            _config.normalizationDivider,
            _config.normalizationMultiplier
        )
    {
        _AGGREGATOR = _config.primaryAggregator;
        _SECONDARY_AGGREGATOR = _config.secondaryAggregator;
        _SECONDARY_HEARTBEAT = _config.secondaryHeartbeat;
        _CONVERT_TO_QUOTE = address(_config.secondaryAggregator) != address(0);
        _INVERT_SECONDARY_PRICE = _config.invertSecondPrice;
    }

    function getConfig() external view virtual returns (IChainlinkV3Oracle.ChainlinkV3Config memory config) {
        config.primaryAggregator = _AGGREGATOR;
        config.secondaryAggregator = _SECONDARY_AGGREGATOR;
        config.primaryHeartbeat = _HEARTBEAT;
        config.secondaryHeartbeat = _SECONDARY_HEARTBEAT;
        config.normalizationDivider = _DECIMALS_NORMALIZATION_DIVIDER;
        config.normalizationMultiplier = _DECIMALS_NORMALIZATION_MULTIPLIER;
        config.baseToken = _BASE_TOKEN;
        config.quoteToken = _QUOTE_TOKEN;
        config.convertToQuote = _CONVERT_TO_QUOTE;
        config.invertSecondPrice = _INVERT_SECONDARY_PRICE;
    }
}
