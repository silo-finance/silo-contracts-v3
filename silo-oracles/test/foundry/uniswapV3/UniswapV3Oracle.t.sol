// SPDX-License-Identifier: Unlicense
pragma solidity 0.7.6;
pragma abicoder v2;

import {UNISWAPV3_FACTORY} from "../../../constants/Ethereum.sol";

import {UniswapV3OracleFactory} from "../../../contracts/uniswapV3/UniswapV3OracleFactory.sol";
import {UniswapV3Oracle} from "../../../contracts/uniswapV3/UniswapV3Oracle.sol";
import {IUniswapV3Oracle} from "../../../contracts/interfaces/IUniswapV3Oracle.sol";
import {IUniswapV3Factory} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapPools} from "../_common/UniswapPools.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract UniswapV3OracleTest
*/
contract UniswapV3OracleTest is UniswapPools {
    UniswapV3OracleFactory public immutable ORACLE_FACTORY;

    UniswapV3Oracle public immutable PRICE_PROVIDER;
    IUniswapV3Oracle.UniswapV3DeploymentConfig config;

    constructor() UniswapPools(BlockChain.ETHEREUM) {
        initFork(17977506);

        UniswapV3OracleFactory factory = new UniswapV3OracleFactory(IUniswapV3Factory(UNISWAPV3_FACTORY));
        ORACLE_FACTORY = factory;

        config = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["USDC_WETH"], address(tokens["WETH"]), address(tokens["USDC"]), 1800, 120
        );

        PRICE_PROVIDER = factory.create(config, bytes32(0));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_price_Overflow
    */
    function test_UniswapV3Oracle_price_Overflow() public {
        vm.expectRevert("Overflow");
        PRICE_PROVIDER.quote(2 ** 128, address(1));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_revert_whenPriceZero
    */
    function test_UniswapV3Oracle_revert_whenPriceZero() public {
        vm.expectRevert(bytes("ZeroQuote"));
        PRICE_PROVIDER.quote(1e6, address(tokens["WETH"]));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_revert_onQuoteQuote
    */
    function test_UniswapV3Oracle_revert_onQuoteQuote() public {
        vm.expectRevert("UseBaseAmount");
        PRICE_PROVIDER.quote(1e6, address(tokens["USDC"]));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_invalidBaseToken
    */
    function test_UniswapV3Oracle_invalidBaseToken() public {
        vm.expectRevert(bytes("ZeroQuote"));
        PRICE_PROVIDER.quote(1e6, address(tokens["CRV"]));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_supportOLDError
    */
    function test_UniswapV3Oracle_supportOLDError() public {
        // at block 17977506:
        // assetOldestTimestamp: 1692794867
        // block.timestamp: 1692794879
        // available period: 12
        // price: 4.983925969794450679

        UniswapV3Oracle oracle = ORACLE_FACTORY.create(
            IUniswapV3Oracle.UniswapV3DeploymentConfig(
                pools["SP500_WETH"], address(tokens["WETH"]), address(tokens["WETH"]), 15, 120
            ),
            bytes32(0)
        );

        uint32[] memory secondAgos = new uint32[](2);

        secondAgos[0] = 15;
        vm.expectCall(
            0x4532aC4F53871697CbFaE2d86517823c1E68B016, abi.encodeWithSignature("observe(uint32[])", secondAgos)
        );
        secondAgos[0] = 12;
        vm.expectCall(
            0x4532aC4F53871697CbFaE2d86517823c1E68B016, abi.encodeWithSignature("observe(uint32[])", secondAgos)
        );

        oracle.quote(1e10, address(tokens["SP500"]));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_oldestTimestamp
    */
    function test_UniswapV3Oracle_oldestTimestamp() public view {
        // last one is 1692794747
        // oldest is 1692741935
        assertEq(uint256(PRICE_PROVIDER.oldestTimestamp()), 1692741935, "expect to be oldest");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_UniswapV3Oracle_price_gas
    */
    function test_UniswapV3Oracle_price_gas() public {
        uint256 gasStart = gasleft();
        uint256 priceView = PRICE_PROVIDER.quote(1e18, address(tokens["WETH"]));
        uint256 gasSpend = gasStart - gasleft();
        emit log_named_uint("gasSpend", gasSpend);
        assertEq(gasSpend, 80954, "expect optimised gas #1");

        assertEq(priceView, 1641_609559, "expect ETH price in USDC");

        uint256 otherBlock = 17970874;
        initFork(otherBlock);

        UniswapV3OracleFactory factory = new UniswapV3OracleFactory(IUniswapV3Factory(UNISWAPV3_FACTORY));

        config = IUniswapV3Oracle.UniswapV3DeploymentConfig(
            pools["USDC_WETH"], address(tokens["WETH"]), address(tokens["USDC"]), 1800, 120
        );

        UniswapV3Oracle oracle = factory.create(config, bytes32(0));

        gasStart = gasleft();
        priceView = oracle.quote(1e18, address(tokens["WETH"]));
        gasSpend = gasStart - gasleft();
        emit log_named_uint("at block", otherBlock);
        emit log_named_uint("gasSpend", gasSpend);
        assertEq(gasSpend, 50436, "expect optimised gas #1");

        assertEq(priceView, 1657_278376, "expect ETH price in USDC");
    }
}
