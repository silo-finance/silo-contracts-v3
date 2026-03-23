// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";

contract CustomMethodOracleConfig {
    IERC20Metadata internal immutable _BASE_TOKEN; // solhint-disable-line var-name-mixedcase
    IERC20Metadata internal immutable _QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_DIVIDER; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_MULTIPLIER; // solhint-disable-line var-name-mixedcase
    address internal immutable _TARGET; // solhint-disable-line var-name-mixedcase
    bytes4 internal immutable _CALL_SELECTOR; // solhint-disable-line var-name-mixedcase

    constructor(
        ICustomMethodOracle.DeploymentConfig memory _config,
        uint256 _normalizationDivider,
        uint256 _normalizationMultiplier
    ) {
        _BASE_TOKEN = _config.baseToken;
        _QUOTE_TOKEN = _config.quoteToken;
        _NORMALIZATION_DIVIDER = _normalizationDivider;
        _NORMALIZATION_MULTIPLIER = _normalizationMultiplier;
        _TARGET = _config.target;
        _CALL_SELECTOR = _config.callSelector;
    }

    function getConfig() external view returns (ICustomMethodOracle.OracleConfig memory _cfg) {
        _cfg.baseToken = address(_BASE_TOKEN);
        _cfg.quoteToken = address(_QUOTE_TOKEN);
        _cfg.target = _TARGET;
        _cfg.callSelector = _CALL_SELECTOR;
        _cfg.normalizationDivider = _NORMALIZATION_DIVIDER;
        _cfg.normalizationMultiplier = _NORMALIZATION_MULTIPLIER;
    }
}
