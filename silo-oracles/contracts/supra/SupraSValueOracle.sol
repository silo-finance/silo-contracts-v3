// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {Aggregator} from "../_common/Aggregator.sol";
import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ISupraSValueFeed} from "../interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "../interfaces/ISupraSValueOracle.sol";
import {SupraSValueOracleConfig} from "./SupraSValueOracleConfig.sol";

contract SupraSValueOracle is ISupraSValueOracle, ISiloOracle, Initializable, Aggregator, IVersioned {
    SupraSValueOracleConfig public oracleConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _oracleConfig) external initializer {
        oracleConfig = SupraSValueOracleConfig(_oracleConfig);

        // sanity check configuration by reading once
        _readPrice(oracleConfig.getConfig());
    }

    function getConfig() external view returns (ISupraSValueOracle.OracleConfig memory) {
        return oracleConfig.getConfig();
    }

    function readPrice() external view returns (uint256) {
        return _readPrice(oracleConfig.getConfig());
    }

    function quoteToken() external view returns (address) {
        return oracleConfig.getConfig().quoteToken;
    }

    function beforeQuote(address) external pure override {
        // nothing to execute
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory v) {
        v = "SupraSValueOracle 4.7.0";
    }

    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        ISupraSValueOracle.OracleConfig memory cfg = oracleConfig.getConfig();

        require(_baseToken == cfg.baseToken, AssetNotSupported());
        require(_baseAmount <= type(uint128).max, BaseAmountOverflow());

        uint256 assetPrice = _readPrice(cfg);
        require(assetPrice <= type(uint128).max, InvalidPairId());

        quoteAmount = OracleNormalization.normalizePrice({
            _baseAmount: _baseAmount,
            _assetPrice: assetPrice,
            _normalizationDivider: cfg.normalizationDivider,
            _normalizationMultiplier: cfg.normalizationMultiplier
        });

        require(quoteAmount != 0, ZeroQuote());
    }

    function baseToken() public view override returns (address token) {
        return oracleConfig.getConfig().baseToken;
    }

    function _readPrice(ISupraSValueOracle.OracleConfig memory _cfg) internal view returns (uint256 assetPrice) {
        ISupraSValueFeed.PriceFeed memory priceData = _cfg.supraSValueFeed.getSvalue(_cfg.pairId);

        require(priceData.time != 0, TimeStampZero());

        assetPrice = priceData.price;
    }
}
