// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";

import {ICustomMethodOracle} from "silo-oracles/contracts/interfaces/ICustomMethodOracle.sol";
import {ICustomMethodOracleFactory} from "silo-oracles/contracts/interfaces/ICustomMethodOracleFactory.sol";
import {
    CustomMethodOracleFactoryDeploy
} from "silo-oracles/deploy/custom-method/CustomMethodOracleFactoryDeploy.s.sol";
import {
    SiloOraclesFactoriesDeployments,
    SiloOraclesFactoriesContracts
} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";

import {SiloDeployerWithOracle} from "./SiloDeployerWithOracle.sol";

contract _FeedMock {
    uint256 public spotPrice;

    constructor(uint256 _spot) {
        spotPrice = _spot;
    }

    function readUint() external view returns (uint256) {
        return spotPrice;
    }
}

/*
    FOUNDRY_PROFILE=oracles forge test --mc CustomMethodOracleSiloDeployIntegrationTest --ffi -vv
*/
contract CustomMethodOracleSiloDeployIntegrationTest is SiloDeployerWithOracle {
    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_siloDeployer_CustomMethodOracle --ffi -vv
    */
    function test_siloDeployer_CustomMethodOracle() public {
        _deployMarket();

        ICustomMethodOracle oracle = ICustomMethodOracle(address(siloOracle));

        ICustomMethodOracle.OracleConfig memory cfg = oracle.getConfig();

        console2.log("oracle", address(oracle));
        console2.log("oracle.methodSignature() before set", oracle.methodSignature());
        oracle.setMethodSignature("readUint()");
        console2.log("oracle.methodSignature() after set", oracle.methodSignature());
        console2.logBytes4(cfg.callSelector);

        assertEq(
            cfg.callSelector, bytes4(keccak256(abi.encodePacked(oracle.methodSignature()))), "callSelector mismatch"
        );
    }

    function _deployOracleFactory() internal override {
        CustomMethodOracleFactoryDeploy oracleFactoryDeploy = new CustomMethodOracleFactoryDeploy();
        oracleFactoryDeploy.disableDeploymentsSync();
        oracleFactoryDeploy.run();
    }

    function _oracleTxData() internal override returns (ISiloDeployer.OracleCreationTxData memory txData) {
        _FeedMock feed = new _FeedMock(2e8);

        ICustomMethodOracle.DeploymentConfig memory cfg = ICustomMethodOracle.DeploymentConfig({
            baseToken: token0,
            quoteToken: token1,
            target: address(feed),
            callSelector: bytes4(keccak256(abi.encodePacked("readUint()"))),
            priceDecimals: 8
        });

        txData = ISiloDeployer.OracleCreationTxData({
            deployed: address(0),
            factory: address(_resolveCustomMethodOracleFactory()),
            txInput: abi.encodeCall(ICustomMethodOracleFactory.create, (cfg, bytes32(0)))
        });
    }

    function _resolveCustomMethodOracleFactory() internal returns (ICustomMethodOracleFactory factory) {
        factory = ICustomMethodOracleFactory(
            SiloOraclesFactoriesDeployments.get(
                SiloOraclesFactoriesContracts.CUSTOM_METHOD_ORACLE_FACTORY, ChainsLib.chainAlias()
            )
        );
    }
}
