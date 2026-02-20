// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {ManageableOracle} from "silo-oracles/contracts/manageable/ManageableOracle.sol";
import {IManageableOracleFactory} from "silo-oracles/contracts/interfaces/IManageableOracleFactory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";

contract ManageableOracleFactory is Create2Factory, IManageableOracleFactory {
    /// @dev Implementation contract that will be cloned
    IManageableOracle public immutable ORACLE_IMPLEMENTATION;

    mapping(address oracle => bool created) public createdInFactory;

    constructor() {
        ORACLE_IMPLEMENTATION = new ManageableOracle();
    }

    /// @inheritdoc IManageableOracleFactory
    function create(ISiloOracle _oracle, address _owner, uint32 _timelock, bytes32 _externalSalt)
        public
        returns (IManageableOracle manageableOracle)
    {
        manageableOracle = _deployOracle(_externalSalt);
        manageableOracle.initialize(_oracle, _owner, _timelock);
    }

    /// @inheritdoc IManageableOracleFactory
    function create(
        address _underlyingOracleFactory,
        bytes calldata _underlyingOracleInitData,
        address _owner,
        uint32 _timelock,
        bytes32 _externalSalt
    ) external returns (IManageableOracle manageableOracle) {
        address underlyingOracle = _deployUnderlyingOracle(_underlyingOracleFactory, _underlyingOracleInitData);
        manageableOracle = create(ISiloOracle(underlyingOracle), _owner, _timelock, _externalSalt);
    }

    /// @notice Predict the deterministic address of a ManageableOracle that would be created
    /// @param _deployer Address of the account that will deploy the oracle
    /// @param _externalSalt External salt for the CREATE2 deterministic deployment
    /// @return predictedAddress The address where the ManageableOracle would be deployed
    function predictAddress(address _deployer, bytes32 _externalSalt)
        external
        view
        returns (address predictedAddress)
    {
        require(_deployer != address(0), DeployerCannotBeZero());

        bytes32 salt = _createSalt(_deployer, _externalSalt);
        predictedAddress = Clones.predictDeterministicAddress(address(ORACLE_IMPLEMENTATION), salt);
    }

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

    /// @dev Internal helper to create and register a ManageableOracle instance
    /// @param _externalSalt External salt for the CREATE2 deterministic deployment
    /// @return manageableOracle The created ManageableOracle instance
    function _deployOracle(bytes32 _externalSalt) internal returns (IManageableOracle manageableOracle) {
        bytes32 salt = _salt(_externalSalt);

        manageableOracle = IManageableOracle(Clones.cloneDeterministic(address(ORACLE_IMPLEMENTATION), salt));

        createdInFactory[address(manageableOracle)] = true;

        emit ManageableOracleCreated(address(manageableOracle));
    }
}
