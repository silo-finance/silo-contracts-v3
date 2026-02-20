// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {console2} from "forge-std/console2.sol";

import {IPendleOracleHelper} from "silo-oracles/contracts/pendle/interfaces/IPendleOracleHelper.sol";
import {PendleLPTOracle} from "silo-oracles/contracts/pendle/lp-tokens/PendleLPTOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IPendleLPWrapperLike} from "silo-oracles/contracts/pendle/interfaces/IPendleLPWrapperLike.sol";

import {ChainlinkV3OracleFactory} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3OracleFactory.sol";
import {SiloVirtualAsset8DecimalsDeploy} from "silo-oracles/deploy/SiloVirtualAsset8DecimalsDeploy.s.sol";
import {SiloOraclesContracts} from "silo-oracles/deploy/SiloOraclesContracts.sol";
import {OracleConfig} from "silo-oracles/deploy/OraclesDeployments.sol";
import {ChainlinkV3OracleDeploy} from "silo-oracles/deploy/chainlink-v3-oracle/ChainlinkV3OracleDeploy.s.sol";

import {PendleWrapperLPTToSyOracleFactory} from
    "silo-oracles/contracts/pendle/lp-tokens/wrappers/PendleWrapperLPTToSyOracleFactory.sol";

import {PendleWrapperLPTToAssetOracleFactory} from
    "silo-oracles/contracts/pendle/lp-tokens/wrappers/PendleWrapperLPTToAssetOracleFactory.sol";

import {PendleWrapperLPTToSyOracleFactoryDeploy} from
    "silo-oracles/deploy/pendle/PendleWrapperLPTToSyOracleFactoryDeploy.s.sol";

import {PendleWrapperLPTToAssetOracleFactoryDeploy} from
    "silo-oracles/deploy/pendle/PendleWrapperLPTToAssetOracleFactoryDeploy.s.sol";

import {ChainlinkV3OracleFactoryDeploy} from
    "silo-oracles/deploy/chainlink-v3-oracle/ChainlinkV3OracleFactoryDeploy.s.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc PendleWrapperLPTOracle --ffi -vv
*/
contract PendleWrapperLPTOracle is Test {
    uint32 public constant TWAP_DURATION = 30 minutes;

    IPendleOracleHelper public constant PENDLE_ORACLE =
        IPendleOracleHelper(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    // forge-lint: disable-next-line(screaming-snake-case-const)
    IPendleLPWrapperLike public constant sUSDe_WRAPPER =
        IPendleLPWrapperLike(0xaB025d7b57B0902A2797599F3eB07477400e62B0); // Sep

    PendleWrapperLPTToSyOracleFactory factoryToSy;
    PendleWrapperLPTToAssetOracleFactory factoryToAsset;
    ChainlinkV3OracleFactory chainlinkV3Factory;
    ChainlinkV3OracleDeploy chainlinkOracleDeploy;
    PendleLPTOracle oracleSy;
    PendleLPTOracle oracleAsset;

    event PendleWrapperLPTToSyOracleCreated(ISiloOracle indexed pendleWrapperLPTToSyOracle);
    event PendleWrapperLPTToAssetOracleCreated(ISiloOracle indexed pendleWrapperLPTToAssetOracle);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 22672300); // forking block jun 10 2025

        PendleWrapperLPTToSyOracleFactoryDeploy factorySyDeploy = new PendleWrapperLPTToSyOracleFactoryDeploy();
        factorySyDeploy.disableDeploymentsSync();
        factoryToSy = PendleWrapperLPTToSyOracleFactory(factorySyDeploy.run());

        PendleWrapperLPTToAssetOracleFactoryDeploy factoryAssetDeploy =
            new PendleWrapperLPTToAssetOracleFactoryDeploy();
        factoryToAsset = PendleWrapperLPTToAssetOracleFactory(factoryAssetDeploy.run());

        ChainlinkV3OracleFactoryDeploy chainlinkV3FactoryDeploy = new ChainlinkV3OracleFactoryDeploy();
        chainlinkV3Factory = ChainlinkV3OracleFactory(chainlinkV3FactoryDeploy.run());

        chainlinkOracleDeploy = new ChainlinkV3OracleDeploy();

        SiloVirtualAsset8DecimalsDeploy virtualAssetDeploy = new SiloVirtualAsset8DecimalsDeploy();
        virtualAssetDeploy.run();

        address virtualAsset = AddrLib.getAddress(SiloOraclesContracts.SILO_VIRTUAL_ASSET_8_DECIMALS);
        AddrLib.setAddress("SILO_VIRTUAL_USD_8", virtualAsset);
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrapperLPTToSyOracle_deploy --ffi -vv
     */
    function test_wrapperLPTToSyOracle_deploy() public {
        chainlinkOracleDeploy.setUseConfigName(OracleConfig.CHAINLINK_sUSDe_USD);
        ISiloOracle oracle = ISiloOracle(address(chainlinkOracleDeploy.run()));

        vm.expectEmit(false, false, false, false); // check only if the event is emitted
        emit PendleWrapperLPTToSyOracleCreated(ISiloOracle(address(0)));

        ISiloOracle pendleWrapperLPTToSyOracle = factoryToSy.create(oracle, sUSDe_WRAPPER, bytes32(0));

        uint256 price = pendleWrapperLPTToSyOracle.quote(1e18, address(sUSDe_WRAPPER));

        assertEq(price, 2745809640189568598); // ~2.745 USD
    }

    function test_wrapperLPTToAssetOracle_VERSION() public {
        chainlinkOracleDeploy.setUseConfigName(OracleConfig.CHAINLINK_sUSDe_USD);
        ISiloOracle underlyingOracle = ISiloOracle(address(chainlinkOracleDeploy.run()));
        PendleLPTOracle wrapperOracle = PendleLPTOracle(address(factoryToAsset.create(underlyingOracle, sUSDe_WRAPPER, bytes32(0))));

        assertEq(wrapperOracle.VERSION(), "PendleWrapperLPTToAssetOracle 4.0.0", "VERSION");
    }

    function test_wrapperLPTToAssetOracle_baseToken() public {
        chainlinkOracleDeploy.setUseConfigName(OracleConfig.CHAINLINK_sUSDe_USD);
        ISiloOracle underlyingOracle = ISiloOracle(address(chainlinkOracleDeploy.run()));
        PendleLPTOracle wrapperOracle = PendleLPTOracle(address(factoryToAsset.create(underlyingOracle, sUSDe_WRAPPER, bytes32(0))));

        assertEq(wrapperOracle.baseToken(), address(sUSDe_WRAPPER), "baseToken");
    }
    
    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrapperLPTToAssetOracle_deploy --ffi -vv
    */
    function test_wrapperLPTToAssetOracle_deploy() public pure {
        console2.log("TODO missing test");
    }
}
