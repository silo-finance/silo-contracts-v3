// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IDIAOracle} from "../interfaces/IDIAOracle.sol";
import {IDIAOracleV2} from "../external/dia/IDIAOracleV2.sol";
import {Layer1OracleConfig} from "../_common/Layer1OracleConfig.sol";

/// @notice to keep config contract size low (this is the one that will be deployed each time)
/// factory contract take over verification. You should not deploy or use config that was not created by factory.
contract DIAOracleConfig is Layer1OracleConfig {
    /// @dev Oracle deployed for Silo by DIA, all our prices will be submitted to this contract
    IDIAOracleV2 internal immutable _DIA_ORACLEV2; // solhint-disable-line var-name-mixedcase

    /// @dev if set, we will use secondary price to convert to quote
    bool internal immutable _CONVERT_TO_QUOTE; // solhint-disable-line var-name-mixedcase

    /// @dev If TRUE price will be 1/price
    bool internal immutable _INVERT_SECONDARY_PRICE; // solhint-disable-line var-name-mixedcase

    /// @dev all verification should be done by factory
    constructor(IDIAOracle.DIADeploymentConfig memory _config)
        Layer1OracleConfig(
            _config.baseToken,
            _config.quoteToken,
            _config.heartbeat,
            _config.normalizationDivider,
            _config.normalizationMultiplier
        )
    {
        _DIA_ORACLEV2 = _config.diaOracle;
        _CONVERT_TO_QUOTE = bytes(_config.secondaryKey).length != 0;
        _INVERT_SECONDARY_PRICE = _config.invertSecondPrice;
    }

    function getConfig() external view virtual returns (IDIAOracle.DIAConfig memory config) {
        config.diaOracle = _DIA_ORACLEV2;
        config.baseToken = address(_BASE_TOKEN);
        config.quoteToken = address(_QUOTE_TOKEN);
        // Safe: `_HEARTBEAT` is already stored as uint32-compatible config input.
        // forge-lint: disable-next-line(unsafe-typecast)
        config.heartbeat = uint32(_HEARTBEAT);
        config.convertToQuote = _CONVERT_TO_QUOTE;
        config.normalizationDivider = _DECIMALS_NORMALIZATION_DIVIDER;
        config.normalizationMultiplier = _DECIMALS_NORMALIZATION_MULTIPLIER;
        config.invertSecondPrice = _INVERT_SECONDARY_PRICE;
    }
}
