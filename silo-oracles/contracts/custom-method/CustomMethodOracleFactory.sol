// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {OracleFactory} from "../_common/OracleFactory.sol";
import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";
import {ICustomMethodOracleFactory} from "../interfaces/ICustomMethodOracleFactory.sol";
import {CustomMethodOracle} from "./CustomMethodOracle.sol";
import {CustomMethodOracleConfig} from "./CustomMethodOracleConfig.sol";

contract CustomMethodOracleFactory is Create2Factory, OracleFactory, ICustomMethodOracleFactory {
    constructor() OracleFactory(address(new CustomMethodOracle())) {}

    /// @inheritdoc ICustomMethodOracleFactory
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        virtual
        returns (CustomMethodOracle oracle)
    {
        bytes32 id = hashConfig(_config);
        address existing = resolveExistingOracle(id);
        if (existing != address(0)) {
            return CustomMethodOracle(existing);
        }

        verifyConfig(_config);

        bytes4 selector = bytes4(keccak256(bytes(_config.methodSignature)));
        CustomMethodOracleConfig oracleConfig = new CustomMethodOracleConfig(_config, selector);

        oracle = CustomMethodOracle(Clones.cloneDeterministic(ORACLE_IMPLEMENTATION, _salt(_externalSalt)));

        _saveOracle(address(oracle), address(oracleConfig), id);

        oracle.initialize(oracleConfig);
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function hashConfig(ICustomMethodOracle.DeploymentConfig memory _config)
        public
        pure
        virtual
        returns (bytes32 configId)
    {
        configId = keccak256(abi.encode(_config));
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config) public view virtual override {
        if (address(_config.baseToken) == address(0)) revert ICustomMethodOracle.AddressZero();
        if (address(_config.quoteToken) == address(0)) revert ICustomMethodOracle.AddressZero();
        if (_config.target == address(0)) revert ICustomMethodOracle.AddressZero();
        if (address(_config.baseToken) == address(_config.quoteToken)) revert ICustomMethodOracle.TokensAreTheSame();

        if (bytes(_config.methodSignature).length == 0) revert ICustomMethodOracle.EmptyMethodSignature();

        if (_config.normalizationDivider > 1e36) revert ICustomMethodOracle.HugeDivider();
        if (_config.normalizationMultiplier > 1e36) revert ICustomMethodOracle.HugeMultiplier();
        if (_config.normalizationDivider == 0 && _config.normalizationMultiplier == 0) {
            revert ICustomMethodOracle.MultiplierAndDividerZero();
        }
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function resolveExistingOracle(bytes32 _configId) public view virtual returns (address oracle) {
        address cfg = getConfigAddress[_configId];
        oracle = cfg == address(0) ? address(0) : getOracleAddress[cfg];
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function predictAddress(
        ICustomMethodOracle.DeploymentConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) external view virtual returns (address predictedAddress) {
        bytes32 id = hashConfig(_config);
        address existing = resolveExistingOracle(id);
        if (existing != address(0)) return existing;

        if (_deployer == address(0)) revert DeployerCannotBeZero();

        predictedAddress =
            Clones.predictDeterministicAddress(ORACLE_IMPLEMENTATION, _createSalt(_deployer, _externalSalt));
    }
}
