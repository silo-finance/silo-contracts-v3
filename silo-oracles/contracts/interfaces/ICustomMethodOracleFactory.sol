// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICustomMethodOracle} from "./ICustomMethodOracle.sol";

/// @notice Clones `CustomMethodOracle` and deploys `CustomMethodOracleConfig` on each `create`.
/// @dev No reuse or registry of config contracts.
interface ICustomMethodOracleFactory {
    error DeployerCannotBeZero();

    /// @dev In `create`, factory appends `()` to `methodSignature` for selector and clone state.
    /// @dev `_externalSalt` is mixed into CREATE2 salt with deployer nonce.
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (ICustomMethodOracle oracle);

    /// @dev Same validation and normalization as `create`; reverts on invalid config.
    /// @dev Returns divider/multiplier for config.
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config)
        external
        view
        returns (uint256 normalizationDivider, uint256 normalizationMultiplier);

    /// @dev Predicted clone for `_deployer` at current nonce and `_externalSalt`.
    /// @dev Matches the next `create` from that address with the same salt.
    function predictAddress(
        address _deployer,
        bytes32 _externalSalt
    ) external view returns (address predictedAddress);
}
