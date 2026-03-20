// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Oracle that reads a parameterless external view and normalizes it like other Silo oracles.
interface ICustomMethodOracle {
    /// @notice Passed to the factory; `hashConfig` and deployment use the same normalization as `create`.
    /// @dev `target`: every price read is `address(target).staticcall`
    /// with only the method selector (no calldata tail).
    /// `methodSignature`: pass method name without parentheses (e.g. `latestAnswer`); factory always appends `()`.
    /// `priceDecimals`: decimals of value returned by target method.
    struct DeploymentConfig {
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        address target;
        string methodSignature;
        uint8 priceDecimals;
    }

    /// @notice Immutable values read in one shot for `quote` / price reads (see `getConfig`).
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
    error EmptyMethodSignature();
    error BaseTokenDecimalsAbove18();
    /// @dev `10 ** exponent` for normalization would overflow uint256 (keep `baseDecimals + priceDecimals` reasonable).
    error NormalizationScaleTooLarge();
    error AssetNotSupported();
    error BaseAmountOverflow();
    error ZeroQuote();
    error StaticCallFailed();
    error InvalidReturnData();

    /// @notice Canonical signature built by factory from method name + `()`.
    function methodSignature() external view returns (string memory);

    /// @notice Single read of config contract fields used for quoting and debugging.
    function getConfig() external view returns (OracleConfig memory);

    function callData() external view returns (bytes memory);

    function callSelector() external view returns (bytes4);

    function priceTarget() external view returns (address);
}
