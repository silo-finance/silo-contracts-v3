// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";

/// @notice Factory for creating DualOracle instances
interface IDualOracleFactory {
    event DualOracleCreated(address indexed oracle);

    error DeployerCannotBeZero();
    error ZeroFactory();
    error FailedToCreateUnderlyingOracle();

    /// @notice Create a new DualOracle wrapping an existing ISiloOracle
    /// @param _oracle      Primary price source to wrap
    /// @param _owner       Address granted DEFAULT_ADMIN_ROLE (full control)
    /// @param _priceSetter Address granted PRICE_SETTER_ROLE; may be address(0) to skip
    /// @param _timelock    Override-activation timelock in seconds; must be in [MIN_TIMELOCK, MAX_TIMELOCK]
    /// @param _lowerPriceBound  Minimum allowed manual price (18-decimal quote units); must be > 0
    /// @param _upperPriceBound  Maximum allowed manual price (18-decimal quote units); must be > _lowerPriceBound
    /// @param _externalSalt Caller-supplied entropy for the CREATE2 deterministic address
    /// @return dualOracle  The deployed DualOracle instance
    function create(
        ISiloOracle _oracle,
        address _owner,
        address _priceSetter,
        uint32 _timelock,
        uint256 _lowerPriceBound,
        uint256 _upperPriceBound,
        bytes32 _externalSalt
    ) external returns (IDualOracle dualOracle);

    /// @notice Create a new DualOracle, deploying the underlying oracle via a factory call first.
    ///         Primarily used by SiloDeployer to compose oracle creation in a single transaction.
    /// @param _underlyingOracleFactory   Factory address used to deploy the primary oracle
    /// @param _underlyingOracleInitData  Encoded calldata forwarded to the underlying factory
    /// @param _owner       Address granted DEFAULT_ADMIN_ROLE (full control)
    /// @param _priceSetter Address granted PRICE_SETTER_ROLE; may be address(0) to skip
    /// @param _timelock    Override-activation timelock in seconds
    /// @param _lowerPriceBound  Minimum allowed manual price (inclusive, 18-decimal quote units)
    /// @param _upperPriceBound  Maximum allowed manual price (inclusive, 18-decimal quote units)
    /// @param _externalSalt Caller-supplied entropy for the CREATE2 deterministic address
    /// @return dualOracle  The deployed DualOracle instance
    function create(
        address _underlyingOracleFactory,
        bytes calldata _underlyingOracleInitData,
        address _owner,
        address _priceSetter,
        uint32 _timelock,
        uint256 _lowerPriceBound,
        uint256 _upperPriceBound,
        bytes32 _externalSalt
    ) external returns (IDualOracle dualOracle);

    /// @notice Predict the deterministic address of a DualOracle before it is deployed
    /// @param _deployer     Address of the account that will call create()
    /// @param _externalSalt The same external salt that will be passed to create()
    /// @return predictedAddress The address where the DualOracle would be deployed
    function predictAddress(address _deployer, bytes32 _externalSalt)
        external
        view
        returns (address predictedAddress);

    /// @notice The implementation contract that is cloned for every new DualOracle
    // solhint-disable-next-line func-name-mixedcase
    function ORACLE_IMPLEMENTATION() external view returns (IDualOracle);
}
