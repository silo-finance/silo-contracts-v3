// SPDX-License-Identifier: Unlicense
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {UNISWAPV3_FACTORY} from "../../../constants/Ethereum.sol";
import {UniswapV3OracleConfig} from "../../../contracts/uniswapV3/UniswapV3OracleConfig.sol";
import {UniswapPools} from "../_common/UniswapPools.sol";
import {UniswapV3OracleFactory} from "../../../contracts/uniswapV3/UniswapV3OracleFactory.sol";
import {IUniswapV3Oracle} from "../../../contracts/interfaces/IUniswapV3Oracle.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract UniswapV3OracleConfigIntegrationTest
*/
contract UniswapV3OracleConfigIntegrationTest is UniswapPools {
    uint32 constant PERIOD_FOR_AVG_PRICE = 1800;
    uint8 constant BLOCK_TIME = 120;
    uint16 constant REQUIRED_CARDINALITY = uint16(uint256(PERIOD_FOR_AVG_PRICE) * 10 / BLOCK_TIME);

    uint256 constant UKY_CREATION_BLOCK = 17736675;

    UniswapV3OracleFactory public immutable UNISWAPV3_ORACLE_FACTORY;

    constructor() UniswapPools(BlockChain.ETHEREUM) {
        initFork(UKY_CREATION_BLOCK);

        UNISWAPV3_ORACLE_FACTORY = new UniswapV3OracleFactory(IUniswapV3Factory(UNISWAPV3_FACTORY));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleConfig_integration_constructor_pass
    */
    function test_UniswapV3OracleConfig_integration_constructor_pass() public {
        IUniswapV3Oracle.UniswapV3DeploymentConfig memory config = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["USDC_WETH"], address(tokens["WETH"]), address(tokens["USDC"]), PERIOD_FOR_AVG_PRICE, BLOCK_TIME
        );

        UNISWAPV3_ORACLE_FACTORY.create(config, bytes32(0));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleConfig_integration_constructor_InvalidPoolForQuoteToken
    */
    function test_UniswapV3OracleConfig_integration_verifyPool_InvalidPoolForQuoteToken() public {
        IUniswapV3Oracle.UniswapV3DeploymentConfig memory config = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["UKY_WETH"], address(tokens["WETH"]), address(tokens["USDC"]), PERIOD_FOR_AVG_PRICE, BLOCK_TIME
        );

        vm.expectRevert("InvalidPoolForQuoteToken");
        UNISWAPV3_ORACLE_FACTORY.verifyPool(config.pool, config.quoteToken, REQUIRED_CARDINALITY);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleConfig_integration_verifyPool_EmptyPool0
    */
    function test_UniswapV3OracleConfig_integration_verifyPool_EmptyPool0() public {
        IUniswapV3Oracle.UniswapV3DeploymentConfig memory config = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["UKY_WETH"], address(tokens["WETH"]), address(tokens["UKY"]), PERIOD_FOR_AVG_PRICE, BLOCK_TIME
        );

        vm.expectRevert("EmptyPool0");
        UNISWAPV3_ORACLE_FACTORY.verifyPool(config.pool, config.quoteToken, REQUIRED_CARDINALITY);
    }
}
