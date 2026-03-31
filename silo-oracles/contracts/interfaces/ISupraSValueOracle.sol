// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {ISupraOraclePull_V2} from "./ISupraOraclePull_V2.sol";

/// @notice Silo final oracle backed by Supra S-Value feed.
/// @dev Integration flow:
/// 1) Config stores `supraOraclePull` address (not feed address).
/// 2) On each read, oracle resolves current feed via `ISupraOraclePull_V2.checkSupraSValueFeed()`.
/// 3) Oracle reads pair data from resolved feed with `getSvalue(pairId)`.
/// This avoids oracle/config redeploys if Supra rotates feed contract address.
interface ISupraSValueOracle {
    struct DeploymentConfig {
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        ISupraOraclePull_V2 supraOraclePull;
        uint256 pairId;
    }

    struct OracleConfig {
        address baseToken;
        address quoteToken;
        /// @notice Supra oracle-pull contract used to resolve current S-Value feed.
        ISupraOraclePull_V2 supraOraclePull;
        uint256 pairId;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
    }

    event SupraSValueConfigDeployed(address indexed configAddress, uint8 priceDecimals);

    error AddressZero();
    error TokensAreTheSame();
    error AssetNotSupported();
    error BaseAmountOverflow();
    error BaseTokenDecimalsAbove18();
    error PairIdMustBeNonZero();
    error InvalidPairId();
    error TimeStampZero();
    error ZeroQuote();
    error InvalidDecimals();

    function initialize(address _oracleConfig) external;
    
    function getConfig() external view returns (OracleConfig memory);

    function readPrice() external view returns (uint256);
}
