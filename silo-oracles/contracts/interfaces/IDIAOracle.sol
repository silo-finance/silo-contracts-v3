// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {IDIAOracleV2} from "../external/dia/IDIAOracleV2.sol";
import {DIAOracleConfig} from "../dia/DIAOracleConfig.sol";

interface IDIAOracle {
    /// @param diaOracle IDIAOracleV2 Oracle deployed by DIA, DIA prices will be submitted to this contract
    /// @param baseToken base token address
    /// @param quoteToken quote token address
    /// @param heartbeat price must be updated at least once every 24h based on DIA protocol, otherwise something
    /// is wrong, you can provide custom time eg +10 minutes in case update wil be late
    /// @param primaryKey key for primary price
    /// @param secondaryKey if provided, price will be translated to quote using secondary price
    /// both keys must be present in `diaOracle` and we assuming both prices are denominated in same token eg:
    /// primary: ABC/USD, secondary: ETH/USD, result will be ABC/ETH.
    /// @param invertSecondPrice in case we using second price, this flag will tell us if we need to 1/secondPrice
    struct DIADeploymentConfig {
        IDIAOracleV2 diaOracle;
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        uint32 heartbeat;
        string primaryKey;
        string secondaryKey;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
        bool invertSecondPrice;
    }

    struct DIAConfig {
        IDIAOracleV2 diaOracle;
        address baseToken;
        address quoteToken;
        uint32 heartbeat;
        bool convertToQuote;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
        bool invertSecondPrice;
    }

    event DIAConfigDeployed(DIAOracleConfig configAddress);

    error AddressZero();
    error TokensAreTheSame();
    error EmptyPrimaryKey();

    error InvalidKey();
    error OldPrice();
    error OldSecondaryPrice();
    error NotSupported();
    error AssetNotSupported();
    error Overflow();
    error BaseAmountOverflow();
    error HugeDivider();
    error HugeMultiplier();
    error MultiplierAndDividerZero();
    error ZeroQuote();
}
