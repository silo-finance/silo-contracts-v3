// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {WusdPlusUsdAdapter} from "silo-oracles/contracts/custom/WusdPlusUsdAdapter.sol";
import {WusdPlusUsdAdapterDeploy} from "silo-oracles/deploy/WusdPlusUsdAdapterDeploy.sol";

import {IChainlinkV3Oracle} from "silo-oracles/contracts/interfaces/IChainlinkV3Oracle.sol";
import {ChainlinkV3Oracle} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3Oracle.sol";
import {ChainlinkV3OracleFactory} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3OracleFactory.sol";

import {ChainlinkV3OraclesConfigsParser} from
    "silo-oracles/deploy/chainlink-v3-oracle/ChainlinkV3OraclesConfigsParser.sol";

import {
    SiloOraclesFactoriesContracts,
    SiloOraclesFactoriesDeployments
} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";

// FOUNDRY_PROFILE=oracles forge test --mc WusdPlusUsdAdapterTest --ffi -vvv
contract WusdPlusUsdAdapterTest is IntegrationTest {
    uint256 internal constant _FORKING_BLOCK_NUMBER = 284751238;

    string internal constant _ORACLE_CONFIG_NAME = "CHAINLINK_WUSDPlus_USDC";

    ChainlinkV3OracleFactory internal _chainlinkV3OracleFactory;
    WusdPlusUsdAdapter internal _adapter;

    function setUp() public {
        vm.createSelectFork(getChainRpcUrl(ARBITRUM_ONE_ALIAS), _FORKING_BLOCK_NUMBER);

        WusdPlusUsdAdapterDeploy deploy = new WusdPlusUsdAdapterDeploy();
        deploy.disableDeploymentsSync();
        _adapter = deploy.run();

        _chainlinkV3OracleFactory = ChainlinkV3OracleFactory(
            SiloOraclesFactoriesDeployments.get(
                SiloOraclesFactoriesContracts.CHAINLINK_V3_ORACLE_FACTORY, getChainAlias()
            )
        );
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_wusdPlusUsdAdapterWithChainlinkV3Oracle --ffi -vvv
    // TODOD this test must be skipped because factory changed and forked version does not match new code
    function test_skip_wusdPlusUsdAdapterWithChainlinkV3Oracle() public {
        IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory config =
            ChainlinkV3OraclesConfigsParser.getConfig(getChainAlias(), _ORACLE_CONFIG_NAME);

        ChainlinkV3Oracle oracle = _chainlinkV3OracleFactory.create(config, bytes32(0));

        uint256 quoteAmount = oracle.quote(1e18, address(config.baseToken));

        assertEq(quoteAmount, 1182927856851607953);
    }

    // FOUNDRY_PROFILE=oracles forge test --mc WusdPlusUsdAdapterTest --ffi -vvv
    function test_wusdPlusUsdAdapter() public view {
        (
            /*uint80 roundID*/
            ,
            int256 aggregatorPrice,
            /*uint256 startedAt*/
            ,
            /*uint256 priceTimestamp*/
            ,
            /*uint80 answeredInRound*/
        ) = _adapter.latestRoundData();

        assertEq(aggregatorPrice, 118290214);
    }
}
