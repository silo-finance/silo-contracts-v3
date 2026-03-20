// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";
import {ICustomMethodOracleFactory} from "../interfaces/ICustomMethodOracleFactory.sol";
import {CustomMethodOracle} from "./CustomMethodOracle.sol";
import {CustomMethodOracleConfig} from "./CustomMethodOracleConfig.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

contract CustomMethodOracleFactory is Create2Factory, ICustomMethodOracleFactory {
    /// @dev implementation cloned for each `create`; not inherited from `OracleFactory` to avoid config/oracle registries.
    address public immutable ORACLE_IMPLEMENTATION; // solhint-disable-line var-name-mixedcase

    constructor() {
        ORACLE_IMPLEMENTATION = address(new CustomMethodOracle());
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        virtual
        returns (ICustomMethodOracle oracle)
    {
        (uint256 normalizationDivider, uint256 normalizationMultiplier) = verifyConfig(_config);
        string memory canonicalMethod = string.concat(_config.methodSignature, "()");

        CustomMethodOracleConfig oracleConfig = new CustomMethodOracleConfig({
            _config: _config,
            _callSelector: bytes4(abi.encodeWithSignature(canonicalMethod)),
            _normalizationDivider: normalizationDivider,
            _normalizationMultiplier: normalizationMultiplier
        });

        oracle = ICustomMethodOracle(
            Clones.cloneDeterministic({ implementation: ORACLE_IMPLEMENTATION, salt: _salt(_externalSalt) })
        );

        oracle.initialize({ _oracleConfig: address(oracleConfig), _methodSignature: canonicalMethod });

        emit ICustomMethodOracle.CustomMethodConfigDeployed(address(oracleConfig));
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config)
        public
        view
        virtual
        override
        returns (uint256 normalizationDivider, uint256 normalizationMultiplier)
    {
        require(address(_config.baseToken) != address(0), ICustomMethodOracle.AddressZero());
        require(address(_config.quoteToken) != address(0), ICustomMethodOracle.AddressZero());
        require(_config.target != address(0), ICustomMethodOracle.AddressZero());
        require(address(_config.baseToken) != address(_config.quoteToken), ICustomMethodOracle.TokensAreTheSame());

        require(bytes(_config.methodSignature).length != 0, ICustomMethodOracle.EmptyMethodSignature());

        (normalizationDivider, normalizationMultiplier) = OracleNormalization.calculateNormalizationData({
            _baseDecimals: _baseTokenDecimals(_config),
            _priceDecimals: _config.priceDecimals
        });
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function predictAddress(
        ICustomMethodOracle.DeploymentConfig memory,
        address _deployer,
        bytes32 _externalSalt
    ) external view virtual returns (address predictedAddress) {
        require(_deployer != address(0), DeployerCannotBeZero());

        predictedAddress = Clones.predictDeterministicAddress({
            implementation: ORACLE_IMPLEMENTATION,
            salt: _createSalt(_deployer, _externalSalt)
        });
    }

    function _baseTokenDecimals(ICustomMethodOracle.DeploymentConfig memory _config)
        internal
        view
        returns (uint8 baseDecimals)
    {
        uint256 decimals = TokenHelper.assertAndGetDecimals(address(_config.baseToken));
        require(decimals <= 18, ICustomMethodOracle.BaseTokenDecimalsAbove18());
        // forge-lint: disable-next-line(unsafe-typecast)
        baseDecimals = uint8(decimals);
    }
}
