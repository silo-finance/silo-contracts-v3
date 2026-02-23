// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {OracleFactory} from "../_common/OracleFactory.sol";
import {IChainlinkV3Oracle} from "../interfaces/IChainlinkV3Oracle.sol";
import {ChainlinkV3Oracle} from "../chainlinkV3/ChainlinkV3Oracle.sol";
import {ChainlinkV3OracleConfig} from "../chainlinkV3/ChainlinkV3OracleConfig.sol";

contract ChainlinkV3OracleFactory is Create2Factory, OracleFactory {
    constructor() OracleFactory(address(new ChainlinkV3Oracle())) {
        // noting to configure
    }

    function create(
        IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory _config,
        bytes32 _externalSalt
    ) external virtual returns (ChainlinkV3Oracle oracle) {
        bytes32 id = hashConfig(_config);
        ChainlinkV3OracleConfig oracleConfig = ChainlinkV3OracleConfig(getConfigAddress[id]);

        if (address(oracleConfig) != address(0)) {
            // config already exists, so oracle exists as well
            return ChainlinkV3Oracle(getOracleAddress[address(oracleConfig)]);
        }

        verifyConfig(_config);

        oracleConfig = new ChainlinkV3OracleConfig(_config);
        oracle = ChainlinkV3Oracle(Clones.cloneDeterministic(ORACLE_IMPLEMENTATION, _salt(_externalSalt)));

        _saveOracle(address(oracle), address(oracleConfig), id);

        oracle.initialize(oracleConfig);
    }

    function hashConfig(IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory _config)
        public
        virtual
        view
        returns (bytes32 configId)
    {
        configId = keccak256(abi.encode(_config));
    }

    // solhint-disable-next-line code-complexity
    function verifyConfig(IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory _config)
        public
        view
        virtual
        returns (uint256 secondaryPriceDecimals)
    {
        if (address(_config.quoteToken) == address(0)) revert IChainlinkV3Oracle.AddressZero();
        if (address(_config.baseToken) == address(0)) revert IChainlinkV3Oracle.AddressZero();
        if (address(_config.quoteToken) == address(_config.baseToken)) revert IChainlinkV3Oracle.TokensAreTheSame();

        if (address(_config.primaryAggregator) == address(0)) revert IChainlinkV3Oracle.AddressZero();

        if (address(_config.primaryAggregator) == address(_config.secondaryAggregator)) {
            revert IChainlinkV3Oracle.AggregatorsAreTheSame();
        }

        if (address(_config.secondaryAggregator) != address(0)) {
            secondaryPriceDecimals = _config.secondaryAggregator.decimals();
        }

        if (_config.normalizationDivider > 1e36) revert IChainlinkV3Oracle.HugeDivider();
        if (_config.normalizationMultiplier > 1e36) revert IChainlinkV3Oracle.HugeMultiplier();

        if (_config.normalizationDivider == 0 && _config.normalizationMultiplier == 0) {
            revert IChainlinkV3Oracle.MultiplierAndDividerZero();
        }
    }
}
