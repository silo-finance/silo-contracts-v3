// SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {UNISWAPV3_FACTORY} from "../../../constants/Ethereum.sol";
import {UniswapPools} from "../_common/UniswapPools.sol";
import {UniswapV3OracleFactory} from "../../../contracts/uniswapV3/UniswapV3OracleFactory.sol";
import {UniswapV3Oracle} from "../../../contracts/uniswapV3/UniswapV3Oracle.sol";
import {IUniswapV3Oracle} from "../../../contracts/interfaces/IUniswapV3Oracle.sol";
import {IUniswapV3Factory} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --mc UniswapV3OracleFactoryReorgTest
*/
contract UniswapV3OracleFactoryReorgTest is UniswapPools {
    uint256 constant TEST_BLOCK = 17970874;

    address constant POOL = address(0x99999);

    UniswapV3OracleFactory public immutable UNISWAPV3_ORACLE_FACTORY;

    IUniswapV3Oracle.UniswapV3DeploymentConfig creationConfig;

    constructor() UniswapPools(BlockChain.ETHEREUM) {
        initFork(TEST_BLOCK);

        UNISWAPV3_ORACLE_FACTORY = new UniswapV3OracleFactory(IUniswapV3Factory(UNISWAPV3_FACTORY));

        creationConfig = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["USDC_WETH"], address(tokens["WETH"]), address(tokens["USDC"]), 1800, 120
        );
    }

    function test_UniswapV3OracleFactory_reorg() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");

        uint256 snapshot = vm.snapshotState();

        vm.prank(eoa1);
        UniswapV3Oracle oracle1 = UNISWAPV3_ORACLE_FACTORY.create(creationConfig, bytes32(0));

        vm.revertToState(snapshot);

        vm.prank(eoa2);
        UniswapV3Oracle oracle2 = UNISWAPV3_ORACLE_FACTORY.create(creationConfig, bytes32(0));

        assertNotEq(address(oracle1), address(oracle2), "oracle1 == oracle2");
    }
}
