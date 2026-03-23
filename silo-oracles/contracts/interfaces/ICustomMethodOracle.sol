// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Oracle that reads a parameterless external view and normalizes it like other Silo oracles.
interface ICustomMethodOracle {
    /// @dev `target`: every price read is `address(target).staticcall(callSelector)`
    /// with only the method selector (no calldata tail).
    /// `priceDecimals`: decimals of value returned by target method.
    struct DeploymentConfig {
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        address target;
        bytes4 callSelector;
        uint8 priceDecimals;
    }

    /// @notice Immutable values
    struct OracleConfig {
        address baseToken;
        address quoteToken;
        address target;
        bytes4 callSelector;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
    }

    event CustomMethodConfigDeployed(address indexed configAddress);

    error AddressZero();
    error TokensAreTheSame();
    error EmptyCallSelector();
    error BaseTokenDecimalsAbove18();
    error AssetNotSupported();
    error BaseAmountOverflow();
    error ZeroQuote();
    error StaticCallFailed();
    error InvalidReturnData();
    error InvalidMethodSignature();

    /// @param _oracleConfig is `CustomMethodOracleConfig` as `address`
    /// @dev Call only from `CustomMethodOracleFactory.create`.
    function initialize(address _oracleConfig) external;

    /// @notice Set the method signature for the oracle, anyone can set it, 
    /// but it will be validated against the call selector
    function setMethodSignature(string memory _methodSignature) external;

    /// @notice Immutable params from config via `getConfig()`
    function getConfig() external view returns (OracleConfig memory);

    /// @notice Canonical method name + `()` after factory normalization
    function methodSignature() external view returns (string memory);

    /// @notice Read directly the price from the target contract
    function readPrice() external view returns (uint256);
}
