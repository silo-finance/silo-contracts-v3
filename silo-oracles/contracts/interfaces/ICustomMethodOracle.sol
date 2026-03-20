// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Oracle that reads a parameterless external view and normalizes it like other Silo oracles.
interface ICustomMethodOracle {
    /// @dev Configuration for factory `create`.
    /// @param baseToken token priced by this oracle
    /// @param quoteToken denomination of the quote
    /// @param target contract to `staticcall`
    /// @param methodSignature canonical signature of the target method, e.g. `latestAnswer()` (no arguments)
    /// @param normalizationDivider see `OracleNormalization`
    /// @param normalizationMultiplier see `OracleNormalization`
    /// @param returnIsSigned if true, return data is decoded as `int256` (must be > 0); otherwise `uint256`
    struct DeploymentConfig {
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        address target;
        string methodSignature;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
        bool returnIsSigned;
    }

    event CustomMethodConfigDeployed(address indexed configAddress);

    error AddressZero();
    error TokensAreTheSame();
    error EmptyMethodSignature();
    error HugeDivider();
    error HugeMultiplier();
    error MultiplierAndDividerZero();
    error AssetNotSupported();
    error BaseAmountOverflow();
    error ZeroQuote();
    error StaticCallFailed();
    error InvalidReturnData();
    error InvalidSignedPrice();

    /// @notice Canonical method signature string passed at deployment.
    function methodSignature() external view returns (string memory);

    /// @notice Full calldata for the parameterless call (4-byte selector).
    function callData() external view returns (bytes memory);

    /// @notice Selector derived from `methodSignature`.
    function callSelector() external view returns (bytes4);

    /// @notice Target contract for the staticcall.
    function priceTarget() external view returns (address);
}
