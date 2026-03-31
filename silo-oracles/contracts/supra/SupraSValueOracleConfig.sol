// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ISupraSValueOracle} from "../interfaces/ISupraSValueOracle.sol";
import {ISupraOraclePull_V2} from "../interfaces/ISupraOraclePull_V2.sol";

contract SupraSValueOracleConfig {
    address internal immutable _BASE_TOKEN; // solhint-disable-line var-name-mixedcase
    address internal immutable _QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase
    ISupraOraclePull_V2 internal immutable _SUPRA_ORACLE_PULL; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _PAIR_ID; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_DIVIDER; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_MULTIPLIER; // solhint-disable-line var-name-mixedcase

    constructor(ISupraSValueOracle.OracleConfig memory _config) {
        _BASE_TOKEN = _config.baseToken;
        _QUOTE_TOKEN = _config.quoteToken;
        _SUPRA_ORACLE_PULL = _config.supraOraclePull;
        _PAIR_ID = _config.pairId;
        _NORMALIZATION_DIVIDER = _config.normalizationDivider;
        _NORMALIZATION_MULTIPLIER = _config.normalizationMultiplier;
    }

    function getConfig() external view returns (ISupraSValueOracle.OracleConfig memory cfg) {
        cfg.baseToken = _BASE_TOKEN;
        cfg.quoteToken = _QUOTE_TOKEN;
        cfg.supraOraclePull = _SUPRA_ORACLE_PULL;
        cfg.pairId = _PAIR_ID;
        cfg.normalizationDivider = _NORMALIZATION_DIVIDER;
        cfg.normalizationMultiplier = _NORMALIZATION_MULTIPLIER;
    }
}
