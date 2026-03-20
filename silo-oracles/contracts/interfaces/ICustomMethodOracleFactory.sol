// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICustomMethodOracle} from "./ICustomMethodOracle.sol";

/// @notice Clones `CustomMethodOracle`, deploys config; same logical config (after method-string normalization) ⇒ one oracle.
interface ICustomMethodOracleFactory {
    error DeployerCannotBeZero();

    /// @dev `methodSignature` is normalized like in `hashConfig` (factory appends `()`). `_externalSalt` is mixed into CREATE2 salt only.
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (ICustomMethodOracle oracle);

    /// @dev Always appends `()` to `methodSignature` before hashing (pass method name without parentheses).
    function hashConfig(ICustomMethodOracle.DeploymentConfig memory _config) external pure returns (bytes32 configId);

    /// @dev Same checks and normalization math as `create`; reverts on invalid config. Returns values passed to `CustomMethodOracleConfig` (single `decimals()` read; no duplicate `calculateNormalizationData` in `create`).
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config)
        external
        view
        returns (uint256 normalizationDivider, uint256 normalizationMultiplier);

    function resolveExistingOracle(bytes32 _configId) external view returns (address oracle);

    /// @dev Uses `hashConfig`; if that id already exists, returns that oracle instead of a clone address.
    function predictAddress(
        ICustomMethodOracle.DeploymentConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) external view returns (address predictedAddress);
}
