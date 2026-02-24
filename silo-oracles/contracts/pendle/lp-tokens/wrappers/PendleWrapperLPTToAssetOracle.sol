// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {PendleLPTToAssetOracle} from "../PendleLPTToAssetOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IPendleLPWrapperLike} from "silo-oracles/contracts/pendle/interfaces/IPendleLPWrapperLike.sol";

/// @notice Price provider for the wrapped Pendle LP tokens.
/// @dev Wrapped tokens are priced 1:1 with Pendle LP tokens.
contract PendleWrapperLPTToAssetOracle is PendleLPTToAssetOracle {
    IPendleLPWrapperLike public immutable LPT_WRAPPER;

    constructor(
        ISiloOracle _underlyingOracle,
        IPendleLPWrapperLike _lptWrapper
    ) PendleLPTToAssetOracle(_underlyingOracle, _lptWrapper.LP()) {
        LPT_WRAPPER = _lptWrapper;
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override virtual returns (string memory version) {
        version = "PendleWrapperLPTToAssetOracle 4.0.0";
    }

    function _getBaseToken() internal view override returns (address baseToken) {
        baseToken = address(LPT_WRAPPER);
    }
}
