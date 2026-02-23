// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IPendleSYTokenLike} from "silo-oracles/contracts/pendle/interfaces/IPendleSYTokenLike.sol";
import {IPendleMarketV3Like} from "silo-oracles/contracts/pendle/interfaces/IPendleMarketV3Like.sol";
import {PendleLPTOracle} from "./PendleLPTOracle.sol";

/// @notice PendleLPTOracle is an oracle, which multiplies the underlying LP token price by getLpToSyRate from Pendle.
/// This oracle must be deployed using PendleLPTOracleFactory contract. PendleLPTOracle decimals are equal to underlying
/// oracle's decimals. TWAP duration is constant and equal to 30 minutes. UNDERLYING_ORACLE must return the price of 
/// LP token's underlying asset. Quote token of PendleLPTOracle is equal to UNDERLYING_ORACLE quote token.
contract PendleLPTToSyOracle is PendleLPTOracle {
    constructor(ISiloOracle _underlyingOracle, address _market) PendleLPTOracle(_underlyingOracle, _market) {}

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override virtual returns (string memory version) {
        version = "PendleLPTToSyOracle 4.0.0";
    }

    function _getRateLpToUnderlying() internal view override returns (uint256) {
        return PENDLE_ORACLE.getLpToSyRate(PENDLE_MARKET, TWAP_DURATION);
    }

    function _getUnderlyingToken() internal override view returns (address token) {
        (address syToken,,) = IPendleMarketV3Like(PENDLE_MARKET).readTokens();
        token = IPendleSYTokenLike(syToken).yieldToken();
    }
}
