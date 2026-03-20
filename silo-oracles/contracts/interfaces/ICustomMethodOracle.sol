// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Oracle that reads a parameterless external view and normalizes it like other Silo oracles.
interface ICustomMethodOracle {
    /// @notice Passed to the factory; `hashConfig` and deployment use the same normalization as `create`.
    /// @dev `target`: every price read is `address(target).staticcall` with only the method selector (no calldata tail).
    /// `methodSignature`: pass method name without parentheses (e.g. `latestAnswer`); factory always appends `()`.
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

    /// @notice Canonical signature built by factory from method name + `()`.
    function methodSignature() external view returns (string memory);

    function callData() external view returns (bytes memory);

    function callSelector() external view returns (bytes4);

    function priceTarget() external view returns (address);
}
