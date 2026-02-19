// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {
    WstEthToStEthAdapterMainnet, IStEthLike
} from "silo-oracles/contracts/custom/WstEthToStEthAdapterMainnet.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {TokensGenerator} from "../_common/TokensGenerator.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract WstEthToStEthAdapterMainnet
*/

interface IWstEthLike {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

contract WstEthToStEthAdapterMainnetTest is TokensGenerator {
    uint256 constant TEST_BLOCK = 22846446;
    IStEthLike constant STETH = IStEthLike(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    WstEthToStEthAdapterMainnet adapter;

    constructor() TokensGenerator(BlockChain.ETHEREUM) {
        initFork(TEST_BLOCK);
        adapter = new WstEthToStEthAdapterMainnet();
    }

    function test_WstEthToStEthAdapterMainnet_constructor() public view {
        assertEq(address(adapter.STETH()), address(STETH), "STETH address is valid");
        assertTrue(Strings.equal(IERC20Metadata(address(adapter.STETH())).symbol(), "stETH"), "stETH symbol correct");
    }

    function test_WstEthToStEthAdapterMainnet_decimals() public view {
        assertEq(adapter.decimals(), 18, "decimals are 18");
    }

    function test_WstEthToStEthAdapterMainnet_description() public view {
        assertTrue(Strings.equal(adapter.description(), "wstETH / stETH adapter"), "description expected");
    }

    function test_WstEthToStEthAdapterMainnet_latestRoundData_compareToOriginalRate() public {
        AggregatorV3Interface aggregator = AggregatorV3Interface(new WstEthToStEthAdapterMainnet());
        int256 originalRate = int256(STETH.getPooledEthByShares(1 ether));

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            aggregator.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, originalRate);
        assertEq(answer, 1.20727441269505765e18, "rate is ~1.2 in 18 decimals");
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function test_WstEthToStEthAdapterMainnet_latestRoundData_integration() public {
        deal(WSTETH, address(this), 1 ether);
        (, int256 answer,,,) = adapter.latestRoundData();

        assertEq(IERC20Metadata(address(STETH)).balanceOf(address(this)), 0);
        IWstEthLike(WSTETH).unwrap(1 ether);

        assertEq(
            IERC20Metadata(address(STETH)).balanceOf(address(this)),
            SafeCast.toUint256(answer) - 1,
            "received expected value - 1 wei"
        );
    }
}
