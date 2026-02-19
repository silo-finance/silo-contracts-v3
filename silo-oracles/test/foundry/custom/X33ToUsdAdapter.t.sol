// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {X33ToUsdAdapter, AggregatorV3Interface} from "silo-oracles/contracts/custom/X33ToUsdAdapter.sol";
import {Forking} from "silo-oracles/test/foundry/_common/Forking.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {X33ToUsdAdapterDeploy} from "silo-oracles/deploy/X33ToUsdAdapterDeploy.sol";
import {PythAggregatorV3} from "pyth-sdk-solidity/PythAggregatorV3.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract X33ToUsdAdapterTest --ffi
*/
contract X33ToUsdAdapterTest is Forking {
    uint256 constant TEST_BLOCK = 16052525;
    IERC20Metadata constant X33 = IERC20Metadata(0x3333111A391cC08fa51353E9195526A70b333333);
    AggregatorV3Interface constant SHADOW_USD_FEED = AggregatorV3Interface(0x7216D86aed9832B2A5A3c2ca34F9a097F66b53D4);
    X33ToUsdAdapter adapter;

    constructor() Forking(BlockChain.SONIC) {
        initFork(TEST_BLOCK);
        AddrLib.init();
        X33ToUsdAdapterDeploy deploy = new X33ToUsdAdapterDeploy();
        deploy.disableDeploymentsSync();
        adapter = deploy.run();
    }

    function test_X33ToUsdAdapter_constructor() public view {
        assertEq(address(adapter.SHADOW_USD_FEED()), 0x7216D86aed9832B2A5A3c2ca34F9a097F66b53D4);

        // https://www.pyth.network/price-feeds/crypto-shadow-usd
        assertEq(
            PythAggregatorV3(address(adapter.SHADOW_USD_FEED())).priceId(),
            0x6f02ad2b8a307411fc3baedb9876e83efe9fa9f5b752aab8c99f4742c9e5f5d5
        );

        assertEq(address(adapter.X33()), 0x3333111A391cC08fa51353E9195526A70b333333);
        assertEq(adapter.X33().symbol(), "x33");
        assertEq(IERC20Metadata(adapter.X33().asset()).symbol(), "xSHADOW");

        assertEq(adapter.SLASHING_PENALTY_DIVIDER(), int256(2));
        assertEq(adapter.SHARES_QUOTE_SAMPLE(), 10 ** 18);
    }

    function test_X33ToUsdAdapter_description() public view {
        assertEq(adapter.description(), "x33 / USD adapter");
    }

    function test_X33ToUsdAdapter_constructor_reverts() public {
        vm.expectRevert(X33ToUsdAdapter.InvalidShadowUsdFeed.selector);
        new X33ToUsdAdapter(AggregatorV3Interface(address(0)));

        vm.warp(block.timestamp + 60 * 60 * 24);
        vm.expectRevert(X33ToUsdAdapter.InvalidShadowUsdFeed.selector);
        new X33ToUsdAdapter(AggregatorV3Interface(address(0)));

        vm.mockCall(
            address(SHADOW_USD_FEED),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(0), block.timestamp, block.timestamp, uint80(0))
        );

        vm.expectRevert(X33ToUsdAdapter.InvalidShadowUsdFeed.selector);
        new X33ToUsdAdapter(SHADOW_USD_FEED);
    }

    function test_X33ToUsdAdapter_decimals() public view {
        assertEq(adapter.decimals(), SHADOW_USD_FEED.decimals());
        assertEq(adapter.decimals(), 8);
    }

    function test_X33ToUsdAdapter_getRoundData() public {
        vm.expectRevert(X33ToUsdAdapter.NotImplemented.selector);
        adapter.getRoundData(0);
    }

    function test_X33ToUsdAdapter_latestRoundData() public view {
        uint256 vaultRate = adapter.X33().convertToAssets(10 ** 18);
        assertEq(vaultRate, 1351829835613517529);
        assertTrue(vaultRate > 10 ** 18 && vaultRate < 15 * 10 ** 18 / 10, "rate is between 1..1.5");

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        (
            uint80 underlyingRoundId,
            int256 underlyingAnswer,
            uint256 underlyingStartedAt,
            uint256 underlyingUpdatedAt,
            uint80 underlyingAnsweredInRound
        ) = SHADOW_USD_FEED.latestRoundData();

        assertEq(roundId, underlyingRoundId);
        assertEq(startedAt, underlyingStartedAt);
        assertEq(updatedAt, underlyingUpdatedAt);
        assertEq(answeredInRound, underlyingAnsweredInRound);

        assertEq(answer, underlyingAnswer * SafeCast.toInt256(vaultRate) / (2 * 10 ** 18));
        assertEq(answer, 63_5435_1516, "answer is ~63$ with 8 decimals");
        assertEq(underlyingAnswer, 94_0111_1515, "underlying feed answer is ~94$ with 8 decimals");
    }
}
