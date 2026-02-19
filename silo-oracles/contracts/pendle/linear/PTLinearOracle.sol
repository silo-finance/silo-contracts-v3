// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IPTLinearOracleConfig} from "../../interfaces/IPTLinearOracleConfig.sol";
import {IPTLinearOracle} from "../../interfaces/IPTLinearOracle.sol";

import {ISparkLinearDiscountOracle} from "../../pendle/interfaces/ISparkLinearDiscountOracle.sol";

contract PTLinearOracle is IPTLinearOracle, Initializable {
    IPTLinearOracleConfig public oracleConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPTLinearOracle
    function initialize(IPTLinearOracleConfig _configAddress) external virtual initializer {
        require(address(_configAddress) != address(0), EmptyConfigAddress());

        oracleConfig = _configAddress;

        emit PTLinearOracleInitialized(_configAddress);
    }

    /// @inheritdoc AggregatorV3Interface
    /// @notice because this is just a proxy to interface, then only `answer` field will have non zero value
    /// return value is in 18 decimals, not 8 like in chainlink
    function latestRoundData()
        external
        view
        virtual
        override
        returns (uint80, int256 answer, uint256, uint256, uint80)
    {
        IPTLinearOracleConfig.OracleConfig memory cfg = oracleConfig.getConfig();
        // pull price for one token, normalizationDivider is one token in token decimals
        answer = SafeCast.toInt256(quote(cfg.normalizationDivider, cfg.ptToken));
        return (0, answer, 0, 0, 0);
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return oracleConfig.getConfig().hardcodedQuoteToken;
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external view returns (string memory) {
        string memory baseSymbol = TokenHelper.symbol(oracleConfig.getConfig().ptToken);
        string memory quoteSymbol = TokenHelper.symbol(oracleConfig.getConfig().hardcodedQuoteToken);
        return string.concat("PTLinearOracle for ", baseSymbol, " / ", quoteSymbol);
    }

    /// @inheritdoc IPTLinearOracle
    function baseDiscountPerYear() external view returns (uint256 discount) {
        discount = ISparkLinearDiscountOracle(oracleConfig.getConfig().linearOracle).baseDiscountPerYear();
    }

    /// @inheritdoc ISiloOracle
    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external pure returns (uint256) {
        return 1;
    }

    /// @notice not in use, always returns 0s, use latestRoundData instead
    function getRoundData(uint80 /* _roundId */ ) external pure returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken) public view virtual returns (uint256 quoteAmount) {
        IPTLinearOracleConfig oracleCfg = oracleConfig;
        require(address(oracleCfg) != address(0), NotInitialized());

        IPTLinearOracleConfig.OracleConfig memory cfg = oracleCfg.getConfig();

        require(_baseToken == cfg.ptToken, AssetNotSupported());
        require(_baseAmount <= type(uint128).max, BaseAmountOverflow());

        /*
        ptLinearPrice is a simple, deterministic feed that returns a discount factor for a given PT. 
        The factor increases linearly as time passes and converges to 1.0 at maturity, 
        so integrators can price PT conservatively without relying on external market data.
        */
        (, int256 ptLinearPrice,,,) = AggregatorV3Interface(cfg.linearOracle).latestRoundData();

        // Safe: linear discount oracle returns non-negative discount factors.
        // forge-lint: disable-next-line(unsafe-typecast)
        quoteAmount = _baseAmount * uint256(ptLinearPrice) / cfg.normalizationDivider;

        require(quoteAmount != 0, ZeroQuote());
    }
}
