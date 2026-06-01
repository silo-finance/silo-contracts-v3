// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {IDualOracleFactory} from "silo-oracles/contracts/interfaces/IDualOracleFactory.sol";
import {DualOracle} from "silo-oracles/contracts/dualOracle/DualOracle.sol";

/// @title DualOracleFactory
/// @notice Deploys DualOracle minimal-proxy clones via CREATE2.
///         Each clone is independent — ownable, pausable, and configured with its own
///         primary oracle, timelock, and price bounds.
///
///         Two creation paths are supported:
///           1. Wrap an existing ISiloOracle directly.
///           2. Deploy the underlying oracle through a factory call and wrap it atomically.
///
/// @dev Mirrors ManageableOracleFactory architecture.
contract DualOracleFactory is Create2Factory, IDualOracleFactory {
    /// @inheritdoc IDualOracleFactory
    IDualOracle public immutable ORACLE_IMPLEMENTATION; // solhint-disable-line var-name-mixedcase

    /// @notice Tracks every DualOracle deployed through this factory
    mapping(address oracle => bool created) public createdInFactory;

    constructor() {
        ORACLE_IMPLEMENTATION = new DualOracle();
    }

    /// @inheritdoc IDualOracleFactory
    function create(
        address _underlyingOracleFactory,
        bytes calldata _underlyingOracleInitData,
        address _owner,
        uint32 _timelock,
        uint256 _lowerPriceBound,
        uint256 _upperPriceBound,
        bytes32 _externalSalt
    ) external returns (IDualOracle dualOracle) {
        address underlyingOracle = _deployUnderlyingOracle(_underlyingOracleFactory, _underlyingOracleInitData);
        dualOracle = create(
            ISiloOracle(underlyingOracle), _owner, _timelock, _lowerPriceBound, _upperPriceBound, _externalSalt
        );
    }

    /// @inheritdoc IDualOracleFactory
    function predictAddress(address _deployer, bytes32 _externalSalt)
        external
        view
        returns (address predictedAddress)
    {
        require(_deployer != address(0), DeployerCannotBeZero());

        bytes32 salt = _createSalt(_deployer, _externalSalt);
        predictedAddress = Clones.predictDeterministicAddress(address(ORACLE_IMPLEMENTATION), salt);
    }

    /// @inheritdoc IDualOracleFactory
    function create(
        ISiloOracle _oracle,
        address _owner,
        uint32 _timelock,
        uint256 _lowerPriceBound,
        uint256 _upperPriceBound,
        bytes32 _externalSalt
    ) public returns (IDualOracle dualOracle) {
        dualOracle = _deployOracle(_externalSalt);
        DualOracle(address(dualOracle)).initialize(_oracle, _owner, _timelock, _lowerPriceBound, _upperPriceBound);
    }

    /// @dev Calls the underlying oracle factory with arbitrary calldata and decodes the returned address.
    ///      Mirrors ManageableOracleFactory._deployUnderlyingOracle.
    function _deployUnderlyingOracle(address _underlyingOracleFactory, bytes calldata _underlyingOracleInitData)
        internal
        returns (address underlyingOracle)
    {
        require(_underlyingOracleFactory != address(0), ZeroFactory());

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = _underlyingOracleFactory.call(_underlyingOracleInitData);
        require(success && data.length == 32, FailedToCreateUnderlyingOracle());

        underlyingOracle = abi.decode(data, (address));
    }

    /// @dev Clones the implementation deterministically, registers it, and emits the creation event.
    function _deployOracle(bytes32 _externalSalt) internal returns (IDualOracle dualOracle) {
        bytes32 salt = _salt(_externalSalt);

        dualOracle = IDualOracle(Clones.cloneDeterministic(address(ORACLE_IMPLEMENTATION), salt));

        createdInFactory[address(dualOracle)] = true;

        emit DualOracleCreated(address(dualOracle));
    }
}
