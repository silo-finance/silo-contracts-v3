// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {OracleFactory} from "../_common/OracleFactory.sol";
import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";
import {ICustomMethodOracleFactory} from "../interfaces/ICustomMethodOracleFactory.sol";
import {CustomMethodOracle} from "./CustomMethodOracle.sol";
import {CustomMethodOracleConfig} from "./CustomMethodOracleConfig.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

contract CustomMethodOracleFactory is Create2Factory, OracleFactory, ICustomMethodOracleFactory {
    constructor() OracleFactory(address(new CustomMethodOracle())) {}

    /// @inheritdoc ICustomMethodOracleFactory
    function create(ICustomMethodOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        virtual
        returns (CustomMethodOracle oracle)
    {
        string memory canonicalMethod = _canonicalMethodSignature(_config.methodSignature);
        bytes32 id = _hashConfig(_config, canonicalMethod);
        address existing = resolveExistingOracle(id);
        if (existing != address(0)) {
            return CustomMethodOracle(existing);
        }

        verifyConfig(_config);

        ICustomMethodOracle.DeploymentConfig memory config = _config;
        config.methodSignature = canonicalMethod;

        uint8 baseDecimals = _baseTokenDecimals(config);
        (uint256 normalizationDivider, uint256 normalizationMultiplier) =
            _normalizationFromDecimals(baseDecimals, config.priceDecimals);

        bytes4 selector = bytes4(keccak256(bytes(config.methodSignature)));
        CustomMethodOracleConfig oracleConfig =
            new CustomMethodOracleConfig(config, selector, normalizationDivider, normalizationMultiplier);

        oracle = CustomMethodOracle(Clones.cloneDeterministic(ORACLE_IMPLEMENTATION, _salt(_externalSalt)));

        _saveOracle(address(oracle), address(oracleConfig), id);

        oracle.initialize(oracleConfig, config.methodSignature);
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function hashConfig(ICustomMethodOracle.DeploymentConfig memory _config)
        public
        pure
        virtual
        returns (bytes32 configId)
    {
        configId = _hashConfig(_config, _canonicalMethodSignature(_config.methodSignature));
    }

    /// @inheritdoc ICustomMethodOracleFactory
    function verifyConfig(ICustomMethodOracle.DeploymentConfig memory _config) public view virtual override {
        require(address(_config.baseToken) != address(0), ICustomMethodOracle.AddressZero());
        require(address(_config.quoteToken) != address(0), ICustomMethodOracle.AddressZero());
        require(_config.target != address(0), ICustomMethodOracle.AddressZero());
        require(address(_config.baseToken) != address(_config.quoteToken), ICustomMethodOracle.TokensAreTheSame());

        require(bytes(_config.methodSignature).length != 0, ICustomMethodOracle.EmptyMethodSignature());

        uint8 baseDecimals = _baseTokenDecimals(_config);
        _normalizationFromDecimals(baseDecimals, _config.priceDecimals);
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

        require(_deployer != address(0), DeployerCannotBeZero());

        predictedAddress =
            Clones.predictDeterministicAddress(ORACLE_IMPLEMENTATION, _createSalt(_deployer, _externalSalt));
    }

    function _canonicalMethodSignature(string memory _method) internal pure returns (string memory) {
        return string.concat(_method, "()");
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

    /// @dev Maps `baseDecimals` + `priceDecimals` to `OracleNormalization` divider/multiplier so quote is 18 decimals.
    function _normalizationFromDecimals(uint8 _baseDecimals, uint8 _priceDecimals)
        internal
        pure
        returns (uint256 divider, uint256 multiplier)
    {
        uint256 sum = uint256(_baseDecimals) + uint256(_priceDecimals);

        if (sum > 18) {
            uint256 d = sum - 18;
            require(d <= 77, ICustomMethodOracle.NormalizationScaleTooLarge());
            return (10 ** d, 0);
        }

        if (sum < 18) {
            uint256 m = 18 - sum;
            require(m <= 77, ICustomMethodOracle.NormalizationScaleTooLarge());
            return (1, 10 ** m);
        }

        return (1, 0);
    }

    function _hashConfig(ICustomMethodOracle.DeploymentConfig memory _config, string memory _canonicalMethod)
        internal
        pure
        returns (bytes32)
    {
        ICustomMethodOracle.DeploymentConfig memory canonical = _config;
        canonical.methodSignature = _canonicalMethod;
        return keccak256(abi.encode(canonical));
    }
}
