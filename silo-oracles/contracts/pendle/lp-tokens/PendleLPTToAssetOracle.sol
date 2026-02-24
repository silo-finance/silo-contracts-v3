// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IPendleSYTokenLike} from "silo-oracles/contracts/pendle/interfaces/IPendleSYTokenLike.sol";
import {IPendleMarketV3Like} from "silo-oracles/contracts/pendle/interfaces/IPendleMarketV3Like.sol";
import {PendleLPTOracle} from "./PendleLPTOracle.sol";

/// @notice PendleLPTToAssetOracle is an oracle, which multiplies the SY.assetInfo() asset price by LpToAssetRate.
/// This oracle must be deployed using PendleLPTToAssetOracleFactory contract. TWAP duration is constant and equal
/// to 30 minutes. UNDERLYING_ORACLE must return the price of SY.assetInfo() asset. Quote token
/// of PendleLPTToAssetOracle is equal to UNDERLYING_ORACLE quote token. PendleLPTToAssetOracle decimals are equal
/// to underlying oracle's decimals.
/// This oracle must be used for Pendle LP tokens with rebasing underlying assets and other cases with SY-to-asset
/// rate not equal to 100%. These cases are described here
/// https://docs.pendle.finance/Developers/Contracts/StandardizedYield#non-standard-sys
contract PendleLPTToAssetOracle is PendleLPTOracle {
    constructor(ISiloOracle _underlyingOracle, address _market) PendleLPTOracle(_underlyingOracle, _market) {}

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override virtual returns (string memory version) {
        version = "PendleLPTToAssetOracle 4.0.0";
    }

    function _getRateLpToUnderlying() internal view override returns (uint256) {
        return PENDLE_ORACLE.getLpToAssetRate(PENDLE_MARKET, TWAP_DURATION);
    }

    function _getUnderlyingToken() internal virtual view override returns (address token) {
        (address syToken,,) = IPendleMarketV3Like(PENDLE_MARKET).readTokens();
        (, token,) = IPendleSYTokenLike(syToken).assetInfo();
    }
}
