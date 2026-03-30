// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";

import {ISupraSValueFeed} from "silo-oracles/contracts/interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "silo-oracles/contracts/interfaces/ISupraSValueOracle.sol";
import {ISupraSValueOracleFactory} from "silo-oracles/contracts/interfaces/ISupraSValueOracleFactory.sol";
import {SupraSValueOracleFactoryDeploy} from "silo-oracles/deploy/supra/SupraSValueOracleFactoryDeploy.s.sol";
import {
    SiloOraclesFactoriesDeployments,
    SiloOraclesFactoriesContracts
} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";

import {SiloDeployerWithOracle} from "./SiloDeployerWithOracle.sol";

contract _SupraFeedMock is ISupraSValueFeed {
    PriceFeed internal _data;

    constructor(uint256 _price, uint256 _decimals) {
        _data = PriceFeed({round: 1, decimals: _decimals, time: block.timestamp, price: _price});
    }

    function getSvalue(uint256) external view returns (PriceFeed memory) {
        return _data;
    }
}

/*
    FOUNDRY_PROFILE=oracles forge test --mc SupraSValueOracleSiloDeployIntegrationTest --ffi -vv
*/
contract SupraSValueOracleSiloDeployIntegrationTest is SiloDeployerWithOracle {
    function test_siloDeployer_SupraSValueOracle() public {
        _deployMarket();

        ISupraSValueOracle oracle = ISupraSValueOracle(address(siloOracle));
        ISupraSValueOracle.OracleConfig memory cfg = oracle.getConfig();

        console2.log("oracle", address(oracle));
        console2.log("pairId", cfg.pairId);

        assertEq(cfg.baseToken, address(token0), "base token mismatch");
        assertEq(cfg.quoteToken, address(token1), "quote token mismatch");
        assertEq(cfg.pairId, 150, "pair id mismatch");
    }

    function _deployOracleFactory() internal override {
        SupraSValueOracleFactoryDeploy oracleFactoryDeploy = new SupraSValueOracleFactoryDeploy();
        oracleFactoryDeploy.disableDeploymentsSync();
        oracleFactoryDeploy.run();
    }

    function _oracleTxData() internal override returns (ISiloDeployer.OracleCreationTxData memory txData) {
        _SupraFeedMock feed = new _SupraFeedMock(2e8, 8);

        ISupraSValueOracle.DeploymentConfig memory cfg = ISupraSValueOracle.DeploymentConfig({
            baseToken: token0,
            quoteToken: token1,
            supraFeed: address(feed),
            pairId: 150,
            useCustomNormalization: false,
            fallbackPriceDecimals: 0,
            normalizationDivider: 0,
            normalizationMultiplier: 0
        });

        txData = ISiloDeployer.OracleCreationTxData({
            deployed: address(0),
            factory: address(_resolveSupraSValueOracleFactory()),
            txInput: abi.encodeCall(ISupraSValueOracleFactory.create, (cfg, bytes32(0)))
        });
    }

    function _resolveSupraSValueOracleFactory() internal returns (ISupraSValueOracleFactory factory) {
        factory = ISupraSValueOracleFactory(
            SiloOraclesFactoriesDeployments.get(
                SiloOraclesFactoriesContracts.SUPRA_SVALUE_ORACLE_FACTORY, ChainsLib.chainAlias()
            )
        );
    }
}
