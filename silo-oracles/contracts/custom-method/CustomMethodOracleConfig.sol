// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";

/// @dev Deploy only via factory; `methodSignature` lives on the oracle clone, not here.
contract CustomMethodOracleConfig {
    IERC20Metadata internal immutable _BASE_TOKEN; // solhint-disable-line var-name-mixedcase
    IERC20Metadata internal immutable _QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_DIVIDER; // solhint-disable-line var-name-mixedcase
    uint256 internal immutable _NORMALIZATION_MULTIPLIER; // solhint-disable-line var-name-mixedcase
    address internal immutable _TARGET; // solhint-disable-line var-name-mixedcase
    bytes4 internal immutable _CALL_SELECTOR; // solhint-disable-line var-name-mixedcase
    bool internal immutable _RETURN_IS_SIGNED; // solhint-disable-line var-name-mixedcase

    constructor(ICustomMethodOracle.DeploymentConfig memory _config, bytes4 _callSelector) {
        _BASE_TOKEN = _config.baseToken;
        _QUOTE_TOKEN = _config.quoteToken;
        _NORMALIZATION_DIVIDER = _config.normalizationDivider;
        _NORMALIZATION_MULTIPLIER = _config.normalizationMultiplier;
        _TARGET = _config.target;
        _CALL_SELECTOR = _callSelector;
        _RETURN_IS_SIGNED = _config.returnIsSigned;
    }

    function baseToken() external view returns (IERC20Metadata) {
        return _BASE_TOKEN;
    }

    function quoteToken() external view returns (IERC20Metadata) {
        return _QUOTE_TOKEN;
    }

    function target() external view returns (address) {
        return _TARGET;
    }

    function callSelector() external view returns (bytes4) {
        return _CALL_SELECTOR;
    }

    function returnIsSigned() external view returns (bool) {
        return _RETURN_IS_SIGNED;
    }

    function normalizationDivider() external view returns (uint256) {
        return _NORMALIZATION_DIVIDER;
    }

    function normalizationMultiplier() external view returns (uint256) {
        return _NORMALIZATION_MULTIPLIER;
    }
}
