// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IUniswapV3Pool} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3OracleConfig} from "../uniswapV3/UniswapV3OracleConfig.sol";

interface IUniswapV3Oracle {
    struct UniswapV3DeploymentConfig {
        // UniV3 pool address that is used for TWAP price
        IUniswapV3Pool pool;

        // Base token
        address baseToken;

        // Asset in which oracle denominates its price
        address quoteToken;

        // TWAP period in seconds.
        // Number of seconds for which time-weighted average should be calculated, ie. 1800 means 30 min
        uint32 periodForAvgPrice;

        // Estimated blockchain block time with 1 decimal, with uint8 max is 25.5s
        uint8 blockTime;
    }

    /// @dev this is UniswapV3DeploymentConfig + quoteToken
    struct UniswapV3Config {
        // UniV3 pool address that is used for TWAP price
        IUniswapV3Pool pool;

        // Base token
        address baseToken;

        // Asset in which oracle denominates its price
        address quoteToken;

        // TWAP period in seconds.
        // Number of seconds for which time-weighted average should be calculated, ie. 1800 means 30 min
        uint32 periodForAvgPrice;

        uint16 requiredCardinality;
    }

    /// @param configAddress UniswapV3OracleConfig config contract address
    event UniswapV3ConfigDeployed(UniswapV3OracleConfig configAddress);
}
