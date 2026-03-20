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

    /// @dev Emitted by `CustomMethodOracleFactory.create` after config + oracle clone are deployed.
    event CustomMethodConfigDeployed(address indexed configAddress);

    error AddressZero();
    error TokensAreTheSame();
    error EmptyMethodSignature();
    error BaseTokenDecimalsAbove18();
    error AssetNotSupported();
    error BaseAmountOverflow();
    error ZeroQuote();
    error StaticCallFailed();
    error InvalidReturnData();

    /// @notice Immutable params from the config contract (one call); `methodSignature` stays on the oracle as public state.
    function getConfig() external view returns (OracleConfig memory);

    /// @notice Canonical method name + `()` after factory normalization; lives on the oracle clone, not on config.
    function methodSignature() external view returns (string memory);

    /// @notice One-off initializer for a fresh clone. `_oracleConfig` is `CustomMethodOracleConfig` as `address` (avoids circular import with that contract).
    /// @dev Intended to be called only from `CustomMethodOracleFactory.create`.
    function initialize(address _oracleConfig, string calldata _methodSignature) external;
}
