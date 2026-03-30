// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

interface ISupraSValueOracle {
    struct DeploymentConfig {
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        address supraFeed;
        uint256 pairId;
        bool useCustomNormalization;
        uint8 fallbackPriceDecimals;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
    }

    struct OracleConfig {
        address baseToken;
        address quoteToken;
        address supraFeed;
        uint256 pairId;
        uint8 priceDecimals;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
    }

    event SupraSValueConfigDeployed(address indexed configAddress);

    error AddressZero();
    error TokensAreTheSame();
    error AssetNotSupported();
    error BaseAmountOverflow();
    error BaseTokenDecimalsAbove18();
    error PairIdMustBeNonZero();
    error InvalidPairId();
    error TimeStampZero();
    error ZeroQuote();
    error InvalidNormalization();
    error HugeDivider();
    error HugeMultiplier();
    error InvalidDecimals();
    error PriceReadFailed();

    function initialize(address _oracleConfig) external;
    function getConfig() external view returns (OracleConfig memory);
    function readPrice() external view returns (uint256);
}
