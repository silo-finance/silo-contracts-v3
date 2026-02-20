// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from  "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {Aggregator} from "../_common/Aggregator.sol";

import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ChainlinkV3OracleConfig} from "./ChainlinkV3OracleConfig.sol";
import {IChainlinkV3Oracle} from "../interfaces/IChainlinkV3Oracle.sol";

// solhint-disable ordering

contract ChainlinkV3Oracle is IChainlinkV3Oracle, ISiloOracle, Initializable, Aggregator, IVersioned {
    ChainlinkV3OracleConfig public oracleConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice validation of config is checked in factory, therefore you should not deploy and initialize directly
    /// use factory always.
    function initialize(ChainlinkV3OracleConfig _configAddress) external virtual initializer {
        oracleConfig = _configAddress;
        emit ChainlinkV3ConfigDeployed(_configAddress);
    }

    /// @inheritdoc ISiloOracle
    // solhint-disable-next-line code-complexity
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        ChainlinkV3Config memory config = oracleConfig.getConfig();

        if (_baseToken != address(config.baseToken)) revert AssetNotSupported();
        if (_baseAmount > type(uint128).max) revert BaseAmountOverflow();

        (bool success, uint256 price) = _getAggregatorPrice(config.primaryAggregator, config.primaryHeartbeat);
        if (!success) revert InvalidPrice();

        if (!config.convertToQuote) {
            quoteAmount = OracleNormalization.normalizePrice(
                _baseAmount, price, config.normalizationDivider, config.normalizationMultiplier
            );

            if (quoteAmount == 0) revert ZeroQuote();
            return quoteAmount;
        }

        (
            bool secondSuccess,
            uint256 secondPrice
        ) = _getAggregatorPrice(config.secondaryAggregator, config.secondaryHeartbeat);

        if (!secondSuccess) revert InvalidSecondPrice();

        quoteAmount = OracleNormalization.normalizePrices(
            _baseAmount,
            price,
            secondPrice,
            config.normalizationDivider,
            config.normalizationMultiplier,
            config.invertSecondPrice
        );

        if (quoteAmount == 0) revert ZeroQuote();
        return quoteAmount;
    }

    /// @dev Returns price directly from aggregator, this method is mostly for debug purposes
    function getAggregatorPrice(bool _primary) external view virtual returns (bool success, uint256 price) {
        IChainlinkV3Oracle.ChainlinkV3Config memory config = oracleConfig.getConfig();

        return _primary
            ? _getAggregatorPrice(config.primaryAggregator, config.primaryHeartbeat)
            : _getAggregatorPrice(config.secondaryAggregator, config.secondaryHeartbeat);
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        IChainlinkV3Oracle.ChainlinkV3Config memory config = oracleConfig.getConfig();
        return address(config.quoteToken);
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "ChainlinkV3Oracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        ChainlinkV3Config memory config = oracleConfig.getConfig();
        return address(config.baseToken);
    }

    function _getAggregatorPrice(AggregatorV3Interface _aggregator, uint256 /* _heartbeat */)
        internal
        view
        virtual
        returns (bool success, uint256 price)
    {
        (
            /*uint80 roundID*/,
            int256 aggregatorPrice,
            /*uint256 startedAt*/,
            /* uint256 priceTimestamp */,
            /*uint80 answeredInRound*/
        ) = _aggregator.latestRoundData();

        if (aggregatorPrice > 0) {
            // Safe: negative values are filtered out by the `aggregatorPrice > 0` check.
            // forge-lint: disable-next-line(unsafe-typecast)
            return (true, uint256(aggregatorPrice));
        }

        return (false, 0);
    }
}
