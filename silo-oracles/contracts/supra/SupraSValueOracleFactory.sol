// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ISupraOraclePull_V2} from "../interfaces/ISupraOraclePull_V2.sol";
import {ISupraSValueFeed} from "../interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "../interfaces/ISupraSValueOracle.sol";
import {ISupraSValueOracleFactory} from "../interfaces/ISupraSValueOracleFactory.sol";
import {SupraSValueOracle} from "./SupraSValueOracle.sol";
import {SupraSValueOracleConfig} from "./SupraSValueOracleConfig.sol";

contract SupraSValueOracleFactory is Create2Factory, ISupraSValueOracleFactory {
    address public immutable ORACLE_IMPLEMENTATION; // solhint-disable-line var-name-mixedcase
    ISupraOraclePull_V2 public immutable SUPRA_ORACLE_PULL; // solhint-disable-line var-name-mixedcase

    constructor(ISupraOraclePull_V2 _supraOraclePull) {
        require(address(_supraOraclePull) != address(0), ISupraSValueOracle.AddressZero());

        SUPRA_ORACLE_PULL = _supraOraclePull;
        ORACLE_IMPLEMENTATION = address(new SupraSValueOracle());
    }

    function create(ISupraSValueOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (ISupraSValueOracle oracle)
    {
        (uint256 divider, uint256 multiplier, uint8 priceDecimals, ISupraSValueFeed supraFeed) = verifyConfig(_config);

        ISupraSValueOracle.OracleConfig memory cfg = ISupraSValueOracle.OracleConfig({
            baseToken: address(_config.baseToken),
            quoteToken: address(_config.quoteToken),
            supraSValueFeed: supraFeed,
            pairId: _config.pairId,
            normalizationDivider: divider,
            normalizationMultiplier: multiplier
        });

        SupraSValueOracleConfig oracleConfig = new SupraSValueOracleConfig(cfg);

        oracle = ISupraSValueOracle(
            Clones.cloneDeterministic({implementation: ORACLE_IMPLEMENTATION, salt: _salt(_externalSalt)})
        );

        oracle.initialize(address(oracleConfig));
        emit ISupraSValueOracle.SupraSValueConfigDeployed(address(oracleConfig), priceDecimals);
    }

    function predictAddress(address _deployer, bytes32 _externalSalt)
        external
        view
        returns (address predictedAddress)
    {
        require(_deployer != address(0), DeployerCannotBeZero());

        predictedAddress = Clones.predictDeterministicAddress({
            implementation: ORACLE_IMPLEMENTATION, salt: _createSalt(_deployer, _externalSalt)
        });
    }

    function verifyConfig(ISupraSValueOracle.DeploymentConfig memory _config)
        public
        view
        returns (
            uint256 normalizationDivider,
            uint256 normalizationMultiplier,
            uint8 priceDecimals,
            ISupraSValueFeed supraFeed
        )
    {
        require(address(_config.baseToken) != address(0), ISupraSValueOracle.AddressZero());
        require(address(_config.quoteToken) != address(0), ISupraSValueOracle.AddressZero());
        require(address(_config.baseToken) != address(_config.quoteToken), ISupraSValueOracle.TokensAreTheSame());

        uint8 baseDecimals = _baseTokenDecimals(_config);
        (priceDecimals, supraFeed) = _readSupraDecimalsAndFeed(_config);

        (normalizationDivider, normalizationMultiplier) = OracleNormalization.calculateNormalizationData({
            _baseDecimals: baseDecimals, _priceDecimals: priceDecimals
        });
    }

    function _baseTokenDecimals(ISupraSValueOracle.DeploymentConfig memory _config)
        internal
        view
        returns (uint8 baseDecimals)
    {
        uint256 decimals = TokenHelper.assertAndGetDecimals(address(_config.baseToken));
        require(decimals <= 18, ISupraSValueOracle.BaseTokenDecimalsAbove18());

        // forge-lint: disable-next-line(unsafe-typecast)
        baseDecimals = uint8(decimals);
    }

    function _readSupraDecimalsAndFeed(ISupraSValueOracle.DeploymentConfig memory _config)
        internal
        view
        returns (uint8 priceDecimals, ISupraSValueFeed supraFeed)
    {
        address supraFeedAddress = SUPRA_ORACLE_PULL.checkSupraSValueFeed();
        require(supraFeedAddress != address(0), ISupraSValueOracle.AddressZero());
        supraFeed = ISupraSValueFeed(supraFeedAddress);

        ISupraSValueFeed.PriceFeed memory data = supraFeed.getSvalue(_config.pairId);
        require(data.time != 0, ISupraSValueOracle.TimeStampZero());
        require(data.decimals <= type(uint8).max, ISupraSValueOracle.InvalidDecimals());

        // forge-lint: disable-next-line(unsafe-typecast)
        priceDecimals = uint8(data.decimals);
    }
}
