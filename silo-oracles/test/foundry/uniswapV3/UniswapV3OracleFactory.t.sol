// SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {IUniswapV3PoolState} from "uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {IUniswapV3PoolImmutables} from "uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";

import {UNISWAPV3_FACTORY} from "../../../constants/Ethereum.sol";
import {UniswapPools} from "../_common/UniswapPools.sol";
import {UniswapV3OracleFactory} from "../../../contracts/uniswapV3/UniswapV3OracleFactory.sol";
import {UniswapV3Oracle} from "../../../contracts/uniswapV3/UniswapV3Oracle.sol";
import {UniswapV3OracleConfig} from "../../../contracts/uniswapV3/UniswapV3OracleConfig.sol";
import {IUniswapV3Oracle} from "../../../contracts/interfaces/IUniswapV3Oracle.sol";
import {IERC20BalanceOf} from "../../../contracts/interfaces/IERC20BalanceOf.sol";
import {IUniswapV3Factory} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --mc UniswapV3OracleFactoryTest
*/
contract UniswapV3OracleFactoryTest is UniswapPools {
    uint256 constant TEST_BLOCK = 17970874;

    uint24 constant FEE = 1000;
    address constant TOKEN_A = address(1);
    address constant TOKEN_B = address(2);
    uint32 constant PERIOD_FOR_AVG_PRICE = 1800;
    uint8 constant BLOCK_TIME = 120;
    // Safe: PERIOD_FOR_AVG_PRICE * 10 / BLOCK_TIME = 1800 * 10 / 120 = 150, which fits in uint16 (max 65535)
    // forge-lint: disable-next-line(unsafe-typecast)
    uint16 constant REQUIRED_CARDINALITY = uint16(uint256(PERIOD_FOR_AVG_PRICE) * 10 / BLOCK_TIME);

    address constant POOL = address(0x99999);

    UniswapV3OracleFactory public immutable UNISWAPV3_ORACLE_FACTORY;

    UniswapV3Oracle public PRICE_PROVIDER;

    IUniswapV3Oracle.UniswapV3DeploymentConfig creationConfig;

    constructor() UniswapPools(BlockChain.ETHEREUM) {
        initFork(TEST_BLOCK);

        UNISWAPV3_ORACLE_FACTORY = new UniswapV3OracleFactory(IUniswapV3Factory(UNISWAPV3_FACTORY));

        creationConfig = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["USDC_WETH"], address(tokens["WETH"]), address(tokens["USDC"]), 1800, 120
        );
    }

    function setUp() public {
        PRICE_PROVIDER = UNISWAPV3_ORACLE_FACTORY.create(creationConfig, bytes32(0));
        _validInitConfig();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_verifyConfig
    */
    function test_UniswapV3OracleFactory_verifyConfig() public {
        IUniswapV3Oracle.UniswapV3DeploymentConfig memory invalidConfig = _validInitConfig();
        invalidConfig.blockTime = 0;

        vm.expectRevert("InvalidBlockTime");
        UNISWAPV3_ORACLE_FACTORY.verifyConfig(invalidConfig);

        invalidConfig = _validInitConfig();
        invalidConfig.periodForAvgPrice = 0;

        vm.expectRevert("InvalidPeriodForAvgPrice");
        UNISWAPV3_ORACLE_FACTORY.verifyConfig(invalidConfig);

        invalidConfig = _validInitConfig();
        invalidConfig.periodForAvgPrice = 0;

        vm.expectRevert("InvalidPeriodForAvgPrice");
        UNISWAPV3_ORACLE_FACTORY.verifyConfig(invalidConfig);

        invalidConfig = _validInitConfig();
        invalidConfig.periodForAvgPrice = uint32(uint256(2 ** 16) * invalidConfig.blockTime / 10);

        vm.expectRevert("InvalidRequiredCardinality");
        UNISWAPV3_ORACLE_FACTORY.verifyConfig(invalidConfig);

        invalidConfig = _validInitConfig();
        invalidConfig.pool = IUniswapV3Pool(address(0));

        vm.expectRevert("EmptyPool");
        UNISWAPV3_ORACLE_FACTORY.verifyConfig(invalidConfig);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_verifyPool_throws_InvalidPoolForQuoteToken
    */
    function test_UniswapV3OracleFactory_verifyPool_throws_InvalidPoolForQuoteToken() public {
        vm.expectRevert("InvalidPoolForQuoteToken");

        UNISWAPV3_ORACLE_FACTORY.verifyPool(IUniswapV3Pool(POOL), address(3), REQUIRED_CARDINALITY);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_verifyPool_throws_InvalidPool
    */
    function test_UniswapV3OracleFactory_verifyPool_throws_InvalidPool() public {
        vm.mockCall(
            UNISWAPV3_FACTORY,
            abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, TOKEN_A, TOKEN_B, FEE),
            abi.encode(address(0))
        );

        vm.expectRevert("InvalidPool");

        UNISWAPV3_ORACLE_FACTORY.verifyPool(IUniswapV3Pool(POOL), TOKEN_A, REQUIRED_CARDINALITY);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_verifyPool_throws_EmptyPoolA
    */
    function test_UniswapV3OracleFactory_verifyPool_throws_EmptyPoolA() public {
        vm.mockCall(TOKEN_A, abi.encodeWithSelector(IERC20BalanceOf.balanceOf.selector, POOL), abi.encode(0));

        vm.expectRevert("EmptyPool0");

        UNISWAPV3_ORACLE_FACTORY.verifyPool(IUniswapV3Pool(POOL), TOKEN_B, REQUIRED_CARDINALITY);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_verifyPool_throws_EmptyPoolB
    */
    function test_UniswapV3OracleFactory_verifyPool_throws_EmptyPoolB() public {
        vm.mockCall(TOKEN_B, abi.encodeWithSelector(IERC20BalanceOf.balanceOf.selector, POOL), abi.encode(0));

        vm.expectRevert("EmptyPool1");

        UNISWAPV3_ORACLE_FACTORY.verifyPool(IUniswapV3Pool(POOL), TOKEN_B, REQUIRED_CARDINALITY);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_verifyPool_throws_BufferNotFull
    */
    function test_UniswapV3OracleFactory_verifyPool_throws_BufferNotFull() public {
        vm.mockCall(
            POOL,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(0, 0, 0, REQUIRED_CARDINALITY - 1, 0, 0, 0)
        );

        vm.expectRevert("BufferNotFull");
        UNISWAPV3_ORACLE_FACTORY.verifyPool(IUniswapV3Pool(POOL), TOKEN_B, REQUIRED_CARDINALITY);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_revert_whenFactoryZero
    */
    function test_UniswapV3OracleFactory_revert_whenFactoryZero() public {
        vm.expectRevert();
        new UniswapV3OracleFactory(IUniswapV3Factory(address(0)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_revert_whenFactoryInvalid
    */
    function test_UniswapV3OracleFactory_revert_whenFactoryInvalid() public {
        vm.expectRevert();
        new UniswapV3OracleFactory(IUniswapV3Factory(address(1)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_initializeOnce
    */
    function test_UniswapV3OracleFactory_initializeOnce() public {
        UniswapV3OracleConfig config = PRICE_PROVIDER.oracleConfig();

        vm.expectRevert("Initializable: contract is already initialized");
        PRICE_PROVIDER.initialize(config);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_create_pass
    */
    function test_UniswapV3OracleFactory_create_pass() public {
        UniswapV3Oracle oracle = UNISWAPV3_ORACLE_FACTORY.create(
            IUniswapV3Oracle.UniswapV3DeploymentConfig(
                pools["CRV_ETH"], address(tokens["CRV"]), address(tokens["WETH"]), 1800, 120
            ),
            bytes32(0)
        );

        assertEq(oracle.quote(3710e18, address(tokens["CRV"])), 1015110362648407264, "expect 3700@$.46 CRV => 1ETH");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_create_reuseConfig
    */
    function test_UniswapV3OracleFactory_create_reuseConfig() public {
        IUniswapV3Oracle.UniswapV3DeploymentConfig memory cfg = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["CRV_ETH"], address(tokens["WETH"]), address(tokens["CRV"]), 1800, 120
        );

        uint256 gasStart = gasleft();
        UniswapV3Oracle oracle1 = UNISWAPV3_ORACLE_FACTORY.create(cfg, bytes32(0));
        uint256 gasEnd = gasleft();

        emit log_named_uint("gas", gasStart - gasEnd);
        assertEq(gasStart - gasEnd, 254142, "optimise gas");

        UniswapV3Oracle oracle2 = UNISWAPV3_ORACLE_FACTORY.create(cfg, bytes32(0));

        assertEq(address(oracle1.oracleConfig()), address(oracle2.oracleConfig()), "expect same config");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_create_whenImplementationInitialised
    */
    function test_UniswapV3OracleFactory_create_whenImplementationInitialised() public {
        UniswapV3Oracle implementation = UniswapV3Oracle(UNISWAPV3_ORACLE_FACTORY.ORACLE_IMPLEMENTATION());

        UniswapV3OracleConfig validConfig = new UniswapV3OracleConfig(creationConfig, 1800 * 10 / 120);
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize(validConfig);

        UniswapV3Oracle oracle = UNISWAPV3_ORACLE_FACTORY.create(
            IUniswapV3Oracle.UniswapV3DeploymentConfig(
                pools["CRV_ETH"], address(tokens["CRV"]), address(tokens["WETH"]), 1800, 120
            ),
            bytes32(0)
        );

        assertEq(oracle.quote(3710e18, address(tokens["CRV"])), 1015110362648407264, "expect 3700@$.46 CRV => 1ETH");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_creationTokensCheck
    */
    function test_UniswapV3OracleFactory_creationTokensCheck() public view {
        assertEq(PRICE_PROVIDER.quoteToken(), address(tokens["USDC"]), "quote token match");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3OracleFactory_creationConfigCheck
    */
    function test_UniswapV3OracleFactory_creationConfigCheck() public view {
        UniswapV3OracleConfig configContract = PRICE_PROVIDER.oracleConfig();
        IUniswapV3Oracle.UniswapV3Config memory config = configContract.getConfig();

        assertEq(
            uint256(config.periodForAvgPrice), uint256(creationConfig.periodForAvgPrice), "periodForAvgPrice match"
        );
        assertEq(
            uint256(config.requiredCardinality),
            uint256(creationConfig.periodForAvgPrice) * 10 / creationConfig.blockTime,
            "requiredCardinality = 30 min (1800) / 12sec => 150 blocks"
        );
        assertEq(address(config.pool), address(creationConfig.pool), "pool match");
        assertEq(config.quoteToken, address(tokens["USDC"]), "quoteToken match");
    }

    function _validInitConfig() internal returns (IUniswapV3Oracle.UniswapV3DeploymentConfig memory) {
        vm.mockCall(POOL, abi.encodeWithSelector(IUniswapV3PoolImmutables.token0.selector), abi.encode(TOKEN_A));
        vm.mockCall(POOL, abi.encodeWithSelector(IUniswapV3PoolImmutables.token1.selector), abi.encode(TOKEN_B));
        vm.mockCall(POOL, abi.encodeWithSelector(IUniswapV3PoolImmutables.fee.selector), abi.encode(FEE));

        vm.mockCall(
            UNISWAPV3_FACTORY,
            abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, TOKEN_A, TOKEN_B, FEE),
            abi.encode(POOL)
        );
        vm.mockCall(
            UNISWAPV3_FACTORY,
            abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, TOKEN_B, TOKEN_A, FEE),
            abi.encode(POOL)
        );

        vm.mockCall(TOKEN_A, abi.encodeWithSelector(IERC20BalanceOf.balanceOf.selector, POOL), abi.encode(1));
        vm.mockCall(TOKEN_B, abi.encodeWithSelector(IERC20BalanceOf.balanceOf.selector, POOL), abi.encode(1));

        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality = REQUIRED_CARDINALITY;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;

        vm.mockCall(
            POOL,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(
                sqrtPriceX96,
                tick,
                observationIndex,
                observationCardinality,
                observationCardinalityNext,
                feeProtocol,
                unlocked
            )
        );

        return IUniswapV3Oracle.UniswapV3DeploymentConfig(
            IUniswapV3Pool(POOL), address(3), address(2), PERIOD_FOR_AVG_PRICE, BLOCK_TIME
        );
    }
}
