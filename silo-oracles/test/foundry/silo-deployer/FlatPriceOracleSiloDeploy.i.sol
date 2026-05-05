// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";

import {IFlatPriceOracleFactory} from "silo-oracles/contracts/interfaces/IFlatPriceOracleFactory.sol";
import {FlatPriceOracleFactoryDeploy} from "silo-oracles/deploy/flat-price/FlatPriceOracleFactoryDeploy.s.sol";
import {
    SiloOraclesFactoriesDeployments,
    SiloOraclesFactoriesContracts
} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";

import {SiloDeployerWithOracle} from "./SiloDeployerWithOracle.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc FlatPriceOracleSiloDeployIntegrationTest --ffi -vv
*/
contract FlatPriceOracleSiloDeployIntegrationTest is SiloDeployerWithOracle {
    uint256 internal constant PRICE = 2e18;

    function test_siloDeployer_FlatPriceOracle() public {
        _deployMarket();

        assertEq(siloOracle.quoteToken(), address(token1), "quote token mismatch");
        assertEq(siloOracle.quote(1e6, address(token0)), PRICE, "quote mismatch");
    }

    function _deployOracleFactory() internal override {
        FlatPriceOracleFactoryDeploy oracleFactoryDeploy = new FlatPriceOracleFactoryDeploy();
        oracleFactoryDeploy.disableDeploymentsSync();
        oracleFactoryDeploy.run();
    }

    function _oracleTxData() internal override returns (ISiloDeployer.OracleCreationTxData memory txData) {
        txData = ISiloDeployer.OracleCreationTxData({
            deployed: address(0),
            factory: address(_resolveFlatPriceOracleFactory()),
            txInput: abi.encodeCall(IFlatPriceOracleFactory.create, (PRICE, address(token0), address(token1), bytes32(0)))
        });
    }

    function _resolveFlatPriceOracleFactory() internal returns (IFlatPriceOracleFactory factory) {
        factory = IFlatPriceOracleFactory(
            SiloOraclesFactoriesDeployments.get(
                SiloOraclesFactoriesContracts.FLAT_PRICE_ORACLE_FACTORY, ChainsLib.chainAlias()
            )
        );
    }
}
