// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ISupraSValueOracle} from "../interfaces/ISupraSValueOracle.sol";
import {ISupraSValueFeed} from "../interfaces/ISupraSValueFeed.sol";

contract SupraSValueOracleConfig {
    address internal immutable _BASE_TOKEN; // solhint-disable-line var-name-mixedcase
    address internal immutable _QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase
    ISupraSValueFeed internal immutable _SUPRA_SVALUE_FEED; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _PAIR_ID; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_DIVIDER; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_MULTIPLIER; // solhint-disable-line var-name-mixedcase

    constructor(ISupraSValueOracle.OracleConfig memory _config) {
        _BASE_TOKEN = _config.baseToken;
        _QUOTE_TOKEN = _config.quoteToken;
        _SUPRA_SVALUE_FEED = _config.supraSValueFeed;
        _PAIR_ID = _config.pairId;
        _NORMALIZATION_DIVIDER = _config.normalizationDivider;
        _NORMALIZATION_MULTIPLIER = _config.normalizationMultiplier;
    }

    function getConfig() external view returns (ISupraSValueOracle.OracleConfig memory cfg) {
        cfg.baseToken = _BASE_TOKEN;
        cfg.quoteToken = _QUOTE_TOKEN;
        cfg.supraSValueFeed = _SUPRA_SVALUE_FEED;
        cfg.pairId = _PAIR_ID;
        cfg.normalizationDivider = _NORMALIZATION_DIVIDER;
        cfg.normalizationMultiplier = _NORMALIZATION_MULTIPLIER;
    }
}
