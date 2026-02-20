// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {PendlePTOracle} from "silo-oracles/contracts/pendle/PendlePTOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {PendlePTOracleFactory} from "silo-oracles/contracts/pendle/PendlePTOracleFactory.sol";
import {PendlePTOracle} from "silo-oracles/contracts/pendle/PendlePTOracle.sol";
import {PendlePTOracleDeploy} from "silo-oracles/deploy/pendle/PendlePTOracleDeploy.s.sol";
import {PendlePTOracleFactoryDeploy} from "silo-oracles/deploy/pendle/PendlePTOracleFactoryDeploy.s.sol";
import {Forking} from "silo-oracles/test/foundry/_common/Forking.sol";
import {IPyYtLpOracleLike} from "silo-oracles/contracts/pendle/interfaces/IPyYtLpOracleLike.sol";
import {SiloOracleMockReturnSame} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMockReturnSame.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract PendlePTOracleTest --ffi
*/
contract PendlePTOracleTest is Forking {
    PendlePTOracleFactory factory;
    PendlePTOracle oracle;
    IPyYtLpOracleLike pendleOracle = IPyYtLpOracleLike(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);
    ISiloOracle underlyingOracle;

    address market = 0x6e4e95FaB7db1f0524b4b0a05F0b9c96380b7Dfa;
    address ptUnderlyingToken = 0x9fb76f7ce5FCeAA2C42887ff441D46095E494206;
    address ptToken = 0xBe27993204Ec64238F71A527B4c4D5F4949034C3;

    event PendlePTOracleCreated(ISiloOracle indexed pendlePTOracle);

    constructor() Forking(BlockChain.SONIC) {
        initFork(11647989); // 1 PT -> 0.9668 underlying
    }

    function setUp() public {
        AddrLib.setAddress(AddrKey.PENDLE_ORACLE, address(pendleOracle));
        PendlePTOracleFactoryDeploy factoryDeploy = new PendlePTOracleFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();
        factory = PendlePTOracleFactory(factoryDeploy.run());

        underlyingOracle = new SiloOracleMockReturnSame();
        PendlePTOracleDeploy oracleDeploy = new PendlePTOracleDeploy();
        AddrLib.setAddress(AddrKey.PENDLE_ORACLE, address(pendleOracle));
        oracleDeploy.setParams(market, underlyingOracle);

        oracle = PendlePTOracle(address(oracleDeploy.run()));
    }

    function test_PendlePTOracle_factory_pendleOracle() public view {
        assertEq(address(factory.PENDLE_ORACLE()), address(pendleOracle), "pendle oracle is set right");
    }

    function test_PendlePTOracle_factory_constructorReverts() public {
        vm.expectRevert(PendlePTOracleFactory.PendleOracleIsZero.selector);
        new PendlePTOracleFactory(IPyYtLpOracleLike(address(0)));
    }

    function test_PendlePTOracle_factory_create_emitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit PendlePTOracleCreated(ISiloOracle(address(0)));

        factory.create(new SiloOracleMockReturnSame(), market, bytes32(0));
    }

    function test_PendlePTOracle_factory_create_updatesMapping() public {
        assertTrue(factory.createdInFactory(factory.create(new SiloOracleMockReturnSame(), market, bytes32(0))));
        assertTrue(factory.createdInFactory(oracle));
    }

    function test_PendlePTOracle_factory_create_canDeployDuplicates() public {
        assertTrue(factory.createdInFactory(factory.create(underlyingOracle, market, bytes32(0))));
        assertTrue(factory.createdInFactory(factory.create(underlyingOracle, market, bytes32(0))));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_PendlePTOracle_VERSION -vv
    */
    function test_PendlePTOracle_VERSION() public view {
        assertEq(oracle.VERSION(), "PendlePTOracle 4.0.0", "VERSION");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_PendlePTOracle_baseToken -vv
    */
    function test_PendlePTOracle_baseToken() public view {
        address baseTokenAddr = oracle.baseToken();
        assertEq(baseTokenAddr, ptToken, "baseToken");

        uint256 amount = 10 ** IERC20Metadata(baseTokenAddr).decimals();
        oracle.quote(amount, baseTokenAddr);
    }

    function test_PendlePTOracle_constructor_state() public view {
        assertEq(oracle.PENDLE_RATE_PRECISION(), 10 ** 18);
        assertEq(oracle.TWAP_DURATION(), 1800);
        assertEq(oracle.PT_TOKEN(), ptToken);
        assertEq(oracle.PT_UNDERLYING_TOKEN(), ptUnderlyingToken);
        assertEq(oracle.MARKET(), market);
        assertEq(address(oracle.UNDERLYING_ORACLE()), address(underlyingOracle));
        assertEq(address(oracle.PENDLE_ORACLE()), address(pendleOracle));
        assertEq(address(oracle.PENDLE_ORACLE()), address(factory.PENDLE_ORACLE()));
        assertEq(oracle.QUOTE_TOKEN(), underlyingOracle.quoteToken());
        assertTrue(oracle.QUOTE_TOKEN() != address(0));
    }

    function test_PendlePTOracle_constructor_doesNotRevertForDifferentDecimals() public {
        vm.mockCall(
            address(ptUnderlyingToken),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(uint8(63))
        );

        assertTrue(address(factory.create(underlyingOracle, market, bytes32(0))) != address(0));
    }

    function test_PendlePTOracle_constructor_revertsInvalidUnderlyingOracle() public {
        vm.mockCall(
            address(underlyingOracle), abi.encodeWithSelector(ISiloOracle.quote.selector), abi.encode(uint256(0))
        );

        vm.expectRevert(PendlePTOracle.InvalidUnderlyingOracle.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTOracle_constructor_revertsPendleOracleNotReady_cardinality() public {
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getOracleState.selector),
            abi.encode(true, 0, true) // increaseCardinalityRequired and oldestObservationSatisfied
        );

        vm.expectRevert(PendlePTOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTOracle_constructor_revertsPendleOracleNotReady_observations() public {
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getOracleState.selector),
            abi.encode(false, 0, false) // increaseCardinalityRequired and oldestObservationSatisfied
        );

        vm.expectRevert(PendlePTOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTOracle_constructor_revertsPendleOracleNotReady_cardinalityAndObservations() public {
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getOracleState.selector),
            abi.encode(true, 0, false) // increaseCardinalityRequired and oldestObservationSatisfied
        );

        vm.expectRevert(PendlePTOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTOracle_constructor_revertsPendleOracleNotReady_integration() public {
        uint256 blockBeforeCardinalityIncrease = 11636735;
        initFork(blockBeforeCardinalityIncrease);
        assertEq(block.number, blockBeforeCardinalityIncrease);

        factory = new PendlePTOracleFactory(pendleOracle);
        vm.expectRevert(PendlePTOracle.PendleOracleNotReady.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTOracle_constructor_revertsPendlePtToSyRateIsZero() public {
        vm.mockCall(
            address(pendleOracle), abi.encodeWithSelector(IPyYtLpOracleLike.getPtToSyRate.selector), abi.encode(0)
        );

        vm.expectRevert(PendlePTOracle.PendlePtToSyRateIsZero.selector);
        factory.create(underlyingOracle, market, bytes32(0));
    }

    function test_PendlePTOracle_quoteToken() public view {
        assertEq(oracle.quoteToken(), oracle.QUOTE_TOKEN());
    }

    function test_PendlePTOracle_getPtToken() public view {
        assertEq(oracle.getPtToken(market), ptToken);
    }

    function test_PendlePTOracle_getPtUnderlyingToken() public view {
        assertEq(oracle.getPtUnderlyingToken(market), ptUnderlyingToken);
    }

    function test_PendlePTOracle_beforeQuote_doesNotRevert() public {
        oracle.beforeQuote(address(0));
    }

    function test_PendlePTOracle_quote_revertsAssetNotSupported() public {
        vm.expectRevert(PendlePTOracle.AssetNotSupported.selector);
        oracle.quote(0, ptUnderlyingToken);
    }

    function test_PendlePTOracle_quote_revertsZeroPrice() public {
        vm.mockCall(address(underlyingOracle), abi.encodeWithSelector(ISiloOracle.quote.selector), abi.encode(0));

        vm.expectRevert(PendlePTOracle.ZeroPrice.selector);
        oracle.quote(0, ptToken);
    }

    function test_PendlePTOracle_quote_rateIsLessThanPrecisionDecimals() public {
        uint256 quoteAmount = 10 ** 18;
        uint256 rateFromPendleOracle = IPyYtLpOracleLike(pendleOracle).getPtToSyRate(market, 1800);

        assertEq(
            underlyingOracle.quote(quoteAmount, address(0)),
            quoteAmount,
            "underlying oracle always returns amount to quote"
        );

        assertEq(
            underlyingOracle.quote(quoteAmount, ptUnderlyingToken),
            quoteAmount,
            "underlying oracle returns amount to quote"
        );

        assertEq(
            oracle.quote(quoteAmount, ptToken),
            rateFromPendleOracle,
            "quote value is equal to ptToSyRate, because underlying oracle returns 10**18 for quote amount"
        );

        assertTrue(rateFromPendleOracle < 10 ** 18);
        assertEq(rateFromPendleOracle, 967114134407545484); // 0.9671141344, close to UI 0.9668

        uint256 newUnderlyingPrice = 15 * 10 ** 18;

        vm.mockCall(
            address(underlyingOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector, quoteAmount, ptUnderlyingToken),
            abi.encode(newUnderlyingPrice)
        );

        assertEq(underlyingOracle.quote(quoteAmount, address(0)), quoteAmount, "price NOT changed for other tokens");
        assertEq(underlyingOracle.quote(quoteAmount, ptToken), quoteAmount, "price NOT changed for other tokens");

        assertEq(
            underlyingOracle.quote(quoteAmount, ptUnderlyingToken),
            newUnderlyingPrice,
            "price changed only for underlying to ensure PT oracle asking underlying price"
        );

        assertEq(oracle.quote(quoteAmount, ptToken), newUnderlyingPrice * rateFromPendleOracle / 10 ** 18);
        assertTrue(oracle.quote(quoteAmount, ptToken) < newUnderlyingPrice);
        assertTrue(oracle.quote(quoteAmount, ptToken) > newUnderlyingPrice * 95 / 100); // rate is ~96.68%
    }

    function test_PendlePTOracle_quote_rateIsMoreThanPrecisionDecimals_rlpMarket() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_MAINNET"))), 22728624);
        ISiloOracle rlpUsdOracle = ISiloOracle(0x6dFD2c79b34D05CC713f7725Db984f3D18B79aaE);
        address rlpMarket = 0x55F06992E4C3ed17Df830dA37644885c0c34EDdA;
        oracle = new PendlePTOracle(rlpUsdOracle, pendleOracle, rlpMarket);

        assertEq(IERC20Metadata(oracle.PT_TOKEN()).decimals(), 6);
        assertEq(IERC20Metadata(oracle.PT_UNDERLYING_TOKEN()).decimals(), 18);

        uint256 underlyingPrice = rlpUsdOracle.quote(10 ** 18, oracle.PT_UNDERLYING_TOKEN());
        assertEq(underlyingPrice, 1.19895478e18, "underlying is 1.20$");

        uint256 ptPrice = oracle.quote(10 ** 6, oracle.PT_TOKEN());
        assertEq(ptPrice, 0.973714918088968959e18, "PT is 0.97$");

        uint256 pendleRate = pendleOracle.getPtToSyRate(rlpMarket, 1800);
        assertEq(
            pendleRate,
            0.812136482819618067081806307831e30,
            "rate has 10**30 precision decimals, expected for 6 and 18 decimals difference"
        );

        assertEq(ptPrice, pendleRate * underlyingPrice / 10 ** (18 + (18 - 6)), "pt price is expected");
    }

    function test_PendlePTOracle_quote_rateIsMoreThanPrecisionDecimals() public {
        // The difference with case above is oracle does scaling for amount to quote in underlying oracle
        // instead of scaling for the price.
        uint256 quoteAmount = 10 ** 18;
        uint256 rateFromPendleOracle = IPyYtLpOracleLike(pendleOracle).getPtToSyRate(market, 1800);

        // Mock rate from Pendle oracle to be more than precision decimals, it will force oracle to execute
        // 'else' branch in the if statement inside quote function.
        vm.mockCall(
            address(pendleOracle),
            abi.encodeWithSelector(IPyYtLpOracleLike.getPtToSyRate.selector, market, 1800),
            abi.encode(rateFromPendleOracle * 10)
        );

        // Ensure the mock worked
        assertEq(IPyYtLpOracleLike(pendleOracle).getPtToSyRate(market, 1800), rateFromPendleOracle * 10);
        assertTrue(IPyYtLpOracleLike(pendleOracle).getPtToSyRate(market, 1800) > oracle.PENDLE_RATE_PRECISION());

        // Rate is >100% now, it is a simulation of decimals diff
        rateFromPendleOracle = IPyYtLpOracleLike(pendleOracle).getPtToSyRate(market, 1800);
        assertEq(rateFromPendleOracle, 9.67114134407545484e18); // 0.9671141344 * 10

        assertEq(
            underlyingOracle.quote(quoteAmount, address(0)),
            quoteAmount,
            "underlying oracle always returns amount to quote"
        );

        assertEq(
            underlyingOracle.quote(quoteAmount, ptUnderlyingToken),
            quoteAmount,
            "underlying oracle returns amount to quote"
        );

        // Amount to quote for underlying oracle was properly scaled, underlying oracle returned the amount to quote.
        // Quote amount was 10**18 before scaling, pendle precision decimals are 18, return value must be equal
        // to PtToSyRate.
        assertEq(
            oracle.quote(quoteAmount, ptToken),
            rateFromPendleOracle,
            "quote value is equal to ptToSyRate, because underlying oracle returns amount to quote"
        );

        // Mock call to underlying oracle with quote amount scaled by the rate. It will ensure that quote function is
        // called with the right args.
        uint256 scaledAmountToQuote = quoteAmount * rateFromPendleOracle / 10 ** 18;
        uint256 newUnderlyingPrice = 15 * 10 ** 18;

        vm.mockCall(
            address(underlyingOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector, scaledAmountToQuote, ptUnderlyingToken),
            abi.encode(newUnderlyingPrice)
        );

        assertEq(underlyingOracle.quote(quoteAmount, ptToken), 10 ** 18, "price NOT changed for other tokens");

        assertEq(underlyingOracle.quote(1, ptUnderlyingToken), 1, "price NOT changed for other amounts to quote");

        assertEq(
            underlyingOracle.quote(scaledAmountToQuote, ptUnderlyingToken),
            newUnderlyingPrice,
            "price changed only for underlying to ensure PT oracle asking underlying price with right args"
        );

        // Scaled amount to quote for underlying oracle was pre-calculated, quote for this value was mocked. Quote from
        // our oracle must be equal to the quote from underlying oracle.
        assertEq(oracle.quote(quoteAmount, ptToken), newUnderlyingPrice, "Returned the quote from underlying oracle");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_PendlePTOracle_reorg -vv
    */
    function test_PendlePTOracle_reorg() public {
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
