// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {ISupraSValueFeed} from "./ISupraSValueFeed.sol";

/// @notice Silo final oracle backed by Supra S-Value feed.
/// @dev Integration flow:
/// 1) Factory resolves current feed via immutable oracle-pull.
/// 2) Resolved feed is stored in oracle config as immutable `supraSValueFeed`.
/// 3) Oracle reads pair data from configured feed with `getSvalue(pairId)`.
interface ISupraSValueOracle {
    struct DeploymentConfig {
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        uint256 pairId;
    }

    struct OracleConfig {
        address baseToken;
        address quoteToken;
        /// @notice Resolved Supra S-Value feed contract used directly for price reads.
        ISupraSValueFeed supraSValueFeed;
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
    error InvalidPairId();
    error TimeStampZero();
    error ZeroQuote();
    error InvalidDecimals();

    function initialize(address _oracleConfig) external;

    function getConfig() external view returns (OracleConfig memory);

    function readPrice() external view returns (uint256);
}
