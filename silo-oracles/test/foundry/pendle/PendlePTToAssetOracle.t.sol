// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {PendlePTToAssetOracle} from "silo-oracles/contracts/pendle/PendlePTToAssetOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {PendlePTToAssetOracleFactory} from "silo-oracles/contracts/pendle/PendlePTToAssetOracleFactory.sol";
import {PendlePTToAssetOracle} from "silo-oracles/contracts/pendle/PendlePTToAssetOracle.sol";
import {PendlePTToAssetOracleDeploy} from "silo-oracles/deploy/pendle/PendlePTToAssetOracleDeploy.s.sol";
import {PendlePTToAssetOracleFactoryDeploy} from "silo-oracles/deploy/pendle/PendlePTToAssetOracleFactoryDeploy.s.sol";
import {Forking} from "silo-oracles/test/foundry/_common/Forking.sol";
import {IPyYtLpOracleLike} from "silo-oracles/contracts/pendle/interfaces/IPyYtLpOracleLike.sol";
import {SiloOracleMockReturnSame} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMockReturnSame.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract PendlePTToAssetOracleTest --ffi
*/
contract PendlePTToAssetOracleTest is Forking {
    PendlePTToAssetOracleFactory factory;
    PendlePTToAssetOracle oracle;
    IPyYtLpOracleLike pendleOracle = IPyYtLpOracleLike(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);
    ISiloOracle underlyingOracle;

    address market = 0x3F5EA53d1160177445B1898afbB16da111182418;
    address syUnderlyingToken = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address ptToken = 0x930441Aa7Ab17654dF5663781CA0C02CC17e6643;

    event PendlePTOracleCreated(ISiloOracle indexed PendlePTOracle);

    constructor() Forking(BlockChain.SONIC) {
        initFork(14690980); // 1 PT -> 0.9558 underlying
    }

    function setUp() public {
        AddrLib.setAddress(AddrKey.PENDLE_ORACLE, address(pendleOracle));
        PendlePTToAssetOracleFactoryDeploy factoryDeploy = new PendlePTToAssetOracleFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();
        factory = PendlePTToAssetOracleFactory(factoryDeploy.run());

        underlyingOracle = new SiloOracleMockReturnSame();
        PendlePTToAssetOracleDeploy oracleDeploy = new PendlePTToAssetOracleDeploy();
        AddrLib.setAddress(AddrKey.PENDLE_ORACLE, address(pendleOracle));
        oracleDeploy.setParams(market, underlyingOracle, factory);

        oracle = PendlePTToAssetOracle(address(oracleDeploy.run()));
    }

    function test_PendlePTToAssetOracle_factory_pendleOracle() public view {
        assertEq(address(factory.PENDLE_ORACLE()), address(pendleOracle), "pendle oracle is set right");
    }

    function test_PendlePTToAssetOracle_factory_constructorReverts() public {
        vm.expectRevert(PendlePTToAssetOracleFactory.PendleOracleIsZero.selector);
        new PendlePTToAssetOracleFactory(IPyYtLpOracleLike(address(0)));
    }

    function test_PendlePTToAssetOracle_factory_create_emitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit PendlePTOracleCreated(ISiloOracle(address(0)));

        factory.create(new SiloOracleMockReturnSame(), market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_factory_create_updatesMapping() public {
        assertTrue(factory.createdInFactory(factory.create(new SiloOracleMockReturnSame(), market, bytes32(0))));
        assertTrue(factory.createdInFactory(oracle));
    }

    function test_PendlePTToAssetOracle_factory_create_canDeployDuplicates() public {
        assertTrue(factory.createdInFactory(factory.create(underlyingOracle, market, bytes32(0))));
        assertTrue(factory.createdInFactory(factory.create(underlyingOracle, market, bytes32(0))));
    }

    function test_PendlePTToAssetOracle_constructor_state() public view {
        assertEq(oracle.PENDLE_RATE_PRECISION(), 10 ** 18);
        assertEq(oracle.TWAP_DURATION(), 1800);
        assertEq(oracle.PT_TOKEN(), ptToken);
        assertEq(oracle.SY_UNDERLYING_TOKEN(), syUnderlyingToken);
        assertEq(IERC20Metadata(syUnderlyingToken).symbol(), "USDC.e");
        assertEq(oracle.MARKET(), market);
        assertEq(address(oracle.UNDERLYING_ORACLE()), address(underlyingOracle));
        assertEq(address(oracle.PENDLE_ORACLE()), address(pendleOracle));
        assertEq(address(oracle.PENDLE_ORACLE()), address(factory.PENDLE_ORACLE()));
        assertEq(oracle.QUOTE_TOKEN(), underlyingOracle.quoteToken());
        assertTrue(oracle.QUOTE_TOKEN() != address(0));
    }

    function test_PendlePTToAssetOracle_constructor_notRevertsInvalidDecimals() public {
        vm.mockCall(
            address(syUnderlyingToken),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(uint8(63))
        );

        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_constructor_revertsInvalidUnderlyingOracle() public {
        vm.mockCall(
            address(underlyingOracle), abi.encodeWithSelector(ISiloOracle.quote.selector), abi.encode(uint256(0))
        );

        vm.expectRevert(PendlePTToAssetOracle.InvalidUnderlyingOracle.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_constructor_revertsPendleOracleNotReady_cardinality() public {
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getOracleState.selector),
            abi.encode(true, 0, true) // increaseCardinalityRequired and oldestObservationSatisfied
        );

        vm.expectRevert(PendlePTToAssetOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_constructor_revertsPendleOracleNotReady_observations() public {
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getOracleState.selector),
            abi.encode(false, 0, false) // increaseCardinalityRequired and oldestObservationSatisfied
        );

        vm.expectRevert(PendlePTToAssetOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_constructor_revertsPendleOracleNotReady_cardinalityAndObservations() public {
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getOracleState.selector),
            abi.encode(true, 0, false) // increaseCardinalityRequired and oldestObservationSatisfied
        );

        vm.expectRevert(PendlePTToAssetOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_constructor_revertsPendleOracleNotReady_integration() public {
        uint256 blockBeforeCardinalityIncrease = 14424702;
        initFork(blockBeforeCardinalityIncrease);
        assertEq(block.number, blockBeforeCardinalityIncrease);

        factory = new PendlePTToAssetOracleFactory(pendleOracle);
        vm.expectRevert(PendlePTToAssetOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_constructor_revertsPPendlePtToAssetRateIsZero() public {
        vm.mockCall(
            address(pendleOracle), abi.encodeWithSelector(IPyYtLpOracleLike.getPtToAssetRate.selector), abi.encode(0)
        );

        vm.expectRevert(PendlePTToAssetOracle.PendlePtToAssetRateIsZero.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTToAssetOracle_quoteToken() public view {
        assertEq(oracle.quoteToken(), oracle.QUOTE_TOKEN());
    }

    function test_PendlePTToAssetOracle_baseToken() public view {
        assertEq(oracle.baseToken(), oracle.PT_TOKEN());
        assertEq(oracle.baseToken(), ptToken);
    }

    function test_PendlePTToAssetOracle_getPtToken() public view {
        assertEq(oracle.getPtToken(market), ptToken);
    }

    function test_PendlePTToAssetOracle_getSyUnderlyingToken() public view {
        assertEq(oracle.getSyUnderlyingToken(market), syUnderlyingToken);
    }

    function test_PendlePTToAssetOracle_beforeQuote_doesNotRevert() public {
        oracle.beforeQuote(address(0));
    }

    function test_PendlePTToAssetOracle_quote_revertsAssetNotSupported() public {
        vm.expectRevert(PendlePTToAssetOracle.AssetNotSupported.selector);
        oracle.quote(0, syUnderlyingToken);
    }

    function test_PendlePTToAssetOracle_quote_revertsZeroPrice() public {
        vm.mockCall(address(underlyingOracle), abi.encodeWithSelector(ISiloOracle.quote.selector), abi.encode(0));

        vm.expectRevert(PendlePTToAssetOracle.ZeroPrice.selector);
        oracle.quote(0, ptToken);
    }

    function test_PendlePTToAssetOracle_quote_rateIsLessThanPrecisionDecimals() public {
        uint256 quoteAmount = 10 ** 18;
        uint256 rateFromPendleOracle = IPyYtLpOracleLike(pendleOracle).getPtToAssetRate(market, 1800);

        assertEq(underlyingOracle.quote(1, address(0)), 1, "underlying oracle always returns same");
        assertEq(underlyingOracle.quote(2, syUnderlyingToken), 2, "underlying oracle returns same");

        assertEq(
            oracle.quote(quoteAmount, ptToken),
            rateFromPendleOracle,
            "quote value is equal to ptToAssetRate, because underlying oracle returns 10**18 for 10**18 input"
        );

        assertTrue(rateFromPendleOracle < 10 ** 18, "<100%");
        assertTrue(rateFromPendleOracle > 95 * 10 ** 18 / 100, ">95%");
        assertEq(rateFromPendleOracle, 955870882090845652);

        uint256 newUnderlyingPrice = 15 * 10 ** 18;

        vm.mockCall(
            address(underlyingOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector, quoteAmount, syUnderlyingToken),
            abi.encode(newUnderlyingPrice)
        );

        assertEq(underlyingOracle.quote(quoteAmount, address(0)), 10 ** 18, "price NOT changed for other tokens");
        assertEq(underlyingOracle.quote(quoteAmount, ptToken), 10 ** 18, "price NOT changed for other tokens");

        assertEq(
            underlyingOracle.quote(quoteAmount, syUnderlyingToken),
            newUnderlyingPrice,
            "price changed only for underlying to ensure PT oracle asking underlying price"
        );

        assertEq(oracle.quote(quoteAmount, ptToken), newUnderlyingPrice * rateFromPendleOracle / 10 ** 18);
        assertTrue(oracle.quote(quoteAmount, ptToken) < newUnderlyingPrice);
        assertTrue(oracle.quote(quoteAmount, ptToken) > newUnderlyingPrice * 95 / 100); // rate is ~95.58%
    }

    function test_PendlePTToAssetOracle_quote_rateIsMoreThanPrecisionDecimals() public {
        uint256 quoteAmount = 10 ** 18;
        uint256 rateFromPendleOracle = IPyYtLpOracleLike(pendleOracle).getPtToAssetRate(market, 1800);

        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getPtToAssetRate.selector, market, 1800),
            abi.encode(rateFromPendleOracle * 100)
        );

        rateFromPendleOracle = IPyYtLpOracleLike(pendleOracle).getPtToAssetRate(market, 1800);
        assertTrue(rateFromPendleOracle > oracle.PENDLE_RATE_PRECISION());

        assertEq(
            oracle.quote(quoteAmount, ptToken),
            rateFromPendleOracle,
            "quote value is equal to ptToSyRate, because underlying oracle returns amount to quote"
        );

        uint256 newUnderlyingPrice = 15 * 10 ** 18;
        uint256 scaledUnderlyingAmount = quoteAmount * rateFromPendleOracle / 10 ** 18;

        vm.mockCall(
            address(underlyingOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector, scaledUnderlyingAmount, syUnderlyingToken),
            abi.encode(newUnderlyingPrice)
        );

        uint256 underlyingScaledQuote = underlyingOracle.quote(scaledUnderlyingAmount, syUnderlyingToken);

        assertEq(
            underlyingScaledQuote,
            newUnderlyingPrice,
            "price is changed only for scaled amount to quote in underlying oracle"
        );

        assertEq(
            oracle.quote(quoteAmount, ptToken),
            underlyingScaledQuote,
            "price is equal to underlying oracle's quote for scaled amount"
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_PendlePTToAssetOracle_reorg -vv
    */
    function test_PendlePTToAssetOracle_reorg() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");

        uint256 snapshot = vm.snapshotState();

        vm.prank(eoa1);
        address oracle1 = address(factory.create(underlyingOracle, market, bytes32(0)));

        vm.revertToState(snapshot);

        vm.prank(eoa2);
        address oracle2 = address(factory.create(underlyingOracle, market, bytes32(0)));

        assertNotEq(oracle1, oracle2, "oracle1 == oracle2");
    }
}
