// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICustomMethodOracle} from "./ICustomMethodOracle.sol";

/// @notice Clones `CustomMethodOracle` and deploys a new `CustomMethodOracleConfig` on every `create` (no reuse / registry).
interface ICustomMethodOracleFactory {
    error DeployerCannotBeZero();

    /// @dev `methodSignature` is normalized in `create` (factory appends `()` for selector and clone state). `_externalSalt` is mixed into CREATE2 salt with deployer nonce.
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (ICustomMethodOracle oracle);

    /// @dev Same checks and normalization math as `create`; reverts on invalid config. Returns divider/multiplier for `CustomMethodOracleConfig` (single `decimals()` read; no duplicate `calculateNormalizationData` in `create`).
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config)
        external
        view
        returns (uint256 normalizationDivider, uint256 normalizationMultiplier);

    /// @dev Address of the next clone for `_deployer` at their current nonce and `_externalSalt` (matches the following `create` from that address with the same salt).
    function predictAddress(
        ICustomMethodOracle.DeploymentConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) external view returns (address predictedAddress);
}
