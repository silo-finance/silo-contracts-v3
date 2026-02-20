// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {OracleFactory} from "../_common/OracleFactory.sol";
import {DIAOracle, IDIAOracle} from "../dia/DIAOracle.sol";
import {DIAOracleConfig} from "../dia/DIAOracleConfig.sol";

contract DIAOracleFactory is Create2Factory, OracleFactory {
    /// @dev decimals in DIA oracle
    uint256 public constant DIA_DECIMALS = 8;

    constructor() OracleFactory(address(new DIAOracle())) {
        // noting to set
    }

    function create(
        IDIAOracle.DIADeploymentConfig calldata _config,
        bytes32 _externalSalt
    ) external virtual returns (DIAOracle oracle)
    {
        bytes32 id = hashConfig(_config);
        DIAOracleConfig oracleConfig = DIAOracleConfig(getConfigAddress[id]);

        if (address(oracleConfig) != address(0)) {
            // config already exists, so oracle exists as well
            return DIAOracle(getOracleAddress[address(oracleConfig)]);
        }

        verifyConfig(_config);

        oracleConfig = new DIAOracleConfig(_config);

        oracle = DIAOracle(Clones.cloneDeterministic(ORACLE_IMPLEMENTATION, _salt(_externalSalt)));

        _saveOracle(address(oracle), address(oracleConfig), id);

        oracle.initialize(oracleConfig, _config.primaryKey, _config.secondaryKey);
    }

    function hashConfig(IDIAOracle.DIADeploymentConfig memory _config)
        public
        virtual
        view
        returns (bytes32 configId)
    {
        configId = keccak256(abi.encode(_config));
    }

    // solhint-disable-next-line code-complexity
    function verifyConfig(IDIAOracle.DIADeploymentConfig calldata _config) public view virtual {
        if (address(_config.diaOracle) == address(0)) revert IDIAOracle.AddressZero();
        if (address(_config.quoteToken) == address(0)) revert IDIAOracle.AddressZero();
        if (address(_config.baseToken) == address(0)) revert IDIAOracle.AddressZero();
        if (address(_config.quoteToken) == address(_config.baseToken)) revert IDIAOracle.TokensAreTheSame();
        if (bytes(_config.primaryKey).length == 0) revert IDIAOracle.EmptyPrimaryKey();
        if (_config.normalizationDivider > 1e36) revert IDIAOracle.HugeDivider();
        if (_config.normalizationMultiplier > 1e36) revert IDIAOracle.HugeMultiplier();
        
        if (_config.normalizationDivider == 0 && _config.normalizationMultiplier == 0) {
            revert IDIAOracle.MultiplierAndDividerZero();
        }
    }
}
