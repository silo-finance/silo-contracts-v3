// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";

/// @notice Factory for creating ManageableOracle instances
interface IManageableOracleFactory {
    event ManageableOracleCreated(address indexed oracle);

    error DeployerCannotBeZero();
    error ZeroFactory();
    error FailedToCreateUnderlyingOracle();

    /// @notice Create a new ManageableOracle
    /// @param _oracle Initial oracle address
    /// @param _owner Address that will own the contract
    /// @param _timelock Initial time lock duration
    /// @param _externalSalt External salt for deterministic address generation
    /// @return manageableOracle The created ManageableOracle instance
    function create(ISiloOracle _oracle, address _owner, uint32 _timelock, bytes32 _externalSalt)
        external
        returns (IManageableOracle manageableOracle);

    /// @notice Create a new ManageableOracle with underlying oracle factory
    /// @param _underlyingOracleFactory Factory address to create the underlying oracle
    /// @param _underlyingOracleInitData Calldata to call the factory and create the underlying oracle
    /// @param _owner Address that will own the contract
    /// @param _timelock Initial time lock duration
    /// @param _externalSalt External salt for deterministic address generation
    /// @return manageableOracle The created ManageableOracle instance
    /// @dev This method is primarily used by SiloDeployer to create the oracle during deployment
    function create(
        address _underlyingOracleFactory,
        bytes calldata _underlyingOracleInitData,
        address _owner,
        uint32 _timelock,
        bytes32 _externalSalt
    ) external returns (IManageableOracle manageableOracle);

    /// @notice Predict the deterministic address of a ManageableOracle that would be created
    /// @param _deployer Address of the account that will deploy the oracle
    /// @param _externalSalt External salt for the CREATE2 deterministic deployment
    /// @return predictedAddress The address where the ManageableOracle would be deployed
    function predictAddress(address _deployer, bytes32 _externalSalt) external view returns (address predictedAddress);

    /// @notice Get the implementation contract that will be cloned
    /// @return The ManageableOracle implementation contract
    // solhint-disable-next-line func-name-mixedcase
    function ORACLE_IMPLEMENTATION() external view returns (IManageableOracle);
}
