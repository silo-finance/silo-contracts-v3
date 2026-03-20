// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICustomMethodOracle} from "./ICustomMethodOracle.sol";
import {CustomMethodOracle} from "../custom-method/CustomMethodOracle.sol";

/// @notice Permissionless factory: clone `CustomMethodOracle` + deploy config; deduplicates by config hash.
interface ICustomMethodOracleFactory {
    error DeployerCannotBeZero();

    /// @notice Deploy (or return existing) oracle for the given configuration.
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (CustomMethodOracle oracle);

    /// @notice Configuration id used for deduplication and lookups.
    function hashConfig(ICustomMethodOracle.DeploymentConfig memory _config) external pure returns (bytes32 configId);

    /// @notice Validate deployment config (also used off-chain before `create`).
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config) external view;

    /// @notice Oracle address for a config id, if already created.
    function resolveExistingOracle(bytes32 _configId) external view returns (address oracle);

    /// @notice Predict clone address for the next `create` from `_deployer` with `_externalSalt`.
    /// @dev If config already exists, returns the existing oracle address instead.
    function predictAddress(
        ICustomMethodOracle.DeploymentConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) external view returns (address predictedAddress);
}
