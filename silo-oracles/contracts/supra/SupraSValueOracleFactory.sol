// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ISupraSValueFeed} from "../interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "../interfaces/ISupraSValueOracle.sol";
import {ISupraSValueOracleFactory} from "../interfaces/ISupraSValueOracleFactory.sol";
import {SupraSValueOracle} from "./SupraSValueOracle.sol";
import {SupraSValueOracleConfig} from "./SupraSValueOracleConfig.sol";

contract SupraSValueOracleFactory is Create2Factory, ISupraSValueOracleFactory {
    address public immutable ORACLE_IMPLEMENTATION; // solhint-disable-line var-name-mixedcase

    constructor() {
        ORACLE_IMPLEMENTATION = address(new SupraSValueOracle());
    }

    function create(ISupraSValueOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (ISupraSValueOracle oracle)
    {
        (uint256 divider, uint256 multiplier, uint8 priceDecimals) = verifyConfig(_config);

        ISupraSValueOracle.OracleConfig memory cfg = ISupraSValueOracle.OracleConfig({
            baseToken: address(_config.baseToken),
            quoteToken: address(_config.quoteToken),
            supraFeed: _config.supraFeed,
            pairId: _config.pairId,
            maxStaleness: _config.maxStaleness,
            priceDecimals: priceDecimals,
            normalizationDivider: divider,
            normalizationMultiplier: multiplier
        });

        SupraSValueOracleConfig oracleConfig = new SupraSValueOracleConfig(cfg);

        oracle =
            ISupraSValueOracle(Clones.cloneDeterministic({implementation: ORACLE_IMPLEMENTATION, salt: _salt(_externalSalt)}));

        oracle.initialize(address(oracleConfig));
        emit ISupraSValueOracle.SupraSValueConfigDeployed(address(oracleConfig));
    }

    function verifyConfig(ISupraSValueOracle.DeploymentConfig memory _config)
        public
        view
        returns (uint256 normalizationDivider, uint256 normalizationMultiplier, uint8 priceDecimals)
    {
        require(address(_config.baseToken) != address(0), ISupraSValueOracle.AddressZero());
        require(address(_config.quoteToken) != address(0), ISupraSValueOracle.AddressZero());
        require(_config.supraFeed != address(0), ISupraSValueOracle.AddressZero());
        require(address(_config.baseToken) != address(_config.quoteToken), ISupraSValueOracle.TokensAreTheSame());
        require(_config.pairId != 0, ISupraSValueOracle.PairIdMustBeNonZero());
        require(_config.maxStaleness != 0, ISupraSValueOracle.MaxStalenessMustBeNonZero());

        uint8 baseDecimals = _baseTokenDecimals(_config);

        if (_config.useCustomNormalization) {
            _validateManualNormalization(_config);
            return (_config.normalizationDivider, _config.normalizationMultiplier, _config.fallbackPriceDecimals);
        }

        priceDecimals = _readSupraDecimals(_config);

        (normalizationDivider, normalizationMultiplier) = OracleNormalization.calculateNormalizationData({
            _baseDecimals: baseDecimals,
            _priceDecimals: priceDecimals
        });
    }

    function predictAddress(address _deployer, bytes32 _externalSalt) external view returns (address predictedAddress) {
        require(_deployer != address(0), DeployerCannotBeZero());

        predictedAddress = Clones.predictDeterministicAddress({
            implementation: ORACLE_IMPLEMENTATION,
            salt: _createSalt(_deployer, _externalSalt)
        });
    }

    function _baseTokenDecimals(ISupraSValueOracle.DeploymentConfig memory _config) internal view returns (uint8 baseDecimals) {
        uint256 decimals = TokenHelper.assertAndGetDecimals(address(_config.baseToken));
        require(decimals <= 18, ISupraSValueOracle.BaseTokenDecimalsAbove18());
        // forge-lint: disable-next-line(unsafe-typecast)
        baseDecimals = uint8(decimals);
    }

    function _readSupraDecimals(ISupraSValueOracle.DeploymentConfig memory _config) internal view returns (uint8 priceDecimals) {
        try ISupraSValueFeed(_config.supraFeed).getSvalue(_config.pairId) returns (ISupraSValueFeed.priceFeed memory data) {
            require(data.price != 0 && data.time != 0, ISupraSValueOracle.InvalidPairId());
            require(data.decimals <= type(uint8).max, ISupraSValueOracle.InvalidDecimals());
            // forge-lint: disable-next-line(unsafe-typecast)
            priceDecimals = uint8(data.decimals);
        } catch {
            require(_config.fallbackPriceDecimals != 0, ISupraSValueOracle.PriceReadFailed());
            priceDecimals = _config.fallbackPriceDecimals;
        }
    }

    function _validateManualNormalization(ISupraSValueOracle.DeploymentConfig memory _config) internal pure {
        require(
            _config.normalizationDivider != 0 || _config.normalizationMultiplier != 0,
            ISupraSValueOracle.InvalidNormalization()
        );
        require(_config.normalizationDivider <= 1e36, ISupraSValueOracle.HugeDivider());
        require(_config.normalizationMultiplier <= 1e36, ISupraSValueOracle.HugeMultiplier());
    }
}
