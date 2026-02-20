// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {DIA_ORACLE_V2} from "../../../constants/Arbitrum.sol";

import {Clones} from "openzeppelin5/proxy/Clones.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {TokensGenerator} from "../_common/TokensGenerator.sol";
import {DIAOracle, DIAOracle, IDIAOracle, IDIAOracleV2} from "../../../contracts/dia/DIAOracle.sol";
import {DIAOracleConfig} from "../../../contracts/dia/DIAOracleConfig.sol";
import {DIAConfigDefault} from "../_common/DIAConfigDefault.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract DIAOracleTest
*/
contract DIAOracleTest is DIAConfigDefault {
    uint256 constant TEST_BLOCK = 124937740;

    DIAOracle public immutable DIA_ORACLE;

    constructor() TokensGenerator(BlockChain.ARBITRUM) {
        initFork(TEST_BLOCK);

        DIAOracleConfig cfg = new DIAOracleConfig(_defaultDIAConfig(10 ** (18 + 8 - 18), 0));
        DIA_ORACLE = DIAOracle(Clones.clone(address(new DIAOracle())));
        DIA_ORACLE.initialize(cfg, _defaultDIAConfig().primaryKey, _defaultDIAConfig().secondaryKey);
    }

    function test_DIAOracle_initialize_OldPrice() public {
        DIAOracle newOracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfig(10 ** (18 + 8 - 18), 0);

        cfg.heartbeat = 1856;
        DIAOracleConfig newConfig = new DIAOracleConfig(cfg);

        newOracle.initialize(newConfig, cfg.primaryKey, cfg.secondaryKey);

        // does not revert
        assertGt(newOracle.quote(1e18, address(tokens["RDPX"])), 0, "does not revert for old price");
    }

    function test_DIAOracle_initialize_OldSecondaryPrice() public {
        DIAOracle newOracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfig(10 ** (18 + 8 - 18), 0);

        // at the block from test, price is 1856s old
        // and ETH price is 6306s old
        cfg.heartbeat = 1857;
        cfg.secondaryKey = "ETH/USD";

        DIAOracleConfig newConfig = new DIAOracleConfig(cfg);
        newOracle.initialize(newConfig, cfg.primaryKey, cfg.secondaryKey);

        assertGt(newOracle.quote(1e18, address(tokens["RDPX"])), 0, "does not revert even for old secondary price");
    }

    function test_DIAOracle_initialize_pass() public {
        DIAOracle newOracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfig(10 ** (18 + 8 - 18), 0);

        DIAOracleConfig newConfig = new DIAOracleConfig(cfg);

        newOracle.initialize(newConfig, cfg.primaryKey, cfg.secondaryKey);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_pass
    */
    function test_DIAOracle_quote_inUSDT() public {
        uint256 price = DIA_ORACLE.quote(1e18, address(tokens["RDPX"]));
        emit log_named_decimal_uint("RDPX/USD", price, 18);
        assertEq(price, 17889972650000000000, "$17,88");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_inUSDC
    */
    function test_DIAOracle_quote_inUSDC() public {
        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfig();
        cfg.quoteToken = IERC20Metadata(address(tokens["USDC"]));
        DIAOracleConfig oracleConfig = new DIAOracleConfig(_defaultDIAConfig(10 ** (18 + 8 - 6), 0));
        DIAOracle oracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        oracle.initialize(oracleConfig, cfg.primaryKey, cfg.secondaryKey);

        uint256 price = oracle.quote(1e18, address(tokens["RDPX"]));
        emit log_named_decimal_uint("RDPX/USD", price, 6);
        assertEq(price, 17889972, "$17,88");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_twoFeeds_noInvert
    */
    function test_DIAOracle_quote_twoFeeds_noInvert() public {
        string memory firstFeed = "RDPX/USD";
        string memory secondFeed = "ETH/USD";

        (uint256 firstFeedValue,) = IDIAOracleV2(DIA_ORACLE_V2).getValue(firstFeed);
        (uint256 secondFeedValue,) = IDIAOracleV2(DIA_ORACLE_V2).getValue(secondFeed);
        uint256 divider = 10 ** (2 * 8); // removes decimals of both feeds

        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfigTwoFeeds({
            _firstFeed: firstFeed,
            _secondFeed: secondFeed,
            _divider: divider,
            _multiplier: 0,
            _invert: false
        });

        uint256 baseTokenDecimals = IERC20Metadata(cfg.baseToken).decimals();
        assertEq(baseTokenDecimals, 18);

        DIAOracleConfig oracleConfig = new DIAOracleConfig(cfg);
        DIAOracle oracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        oracle.initialize(oracleConfig, cfg.primaryKey, cfg.secondaryKey);

        uint256 price = oracle.quote(1e18, address(tokens["RDPX"]));
        assertEq(firstFeedValue / 1e8, 17, "RDPX ~17$");
        assertEq(secondFeedValue / 1e8, 1651, "ETH ~1651$");
        assertEq(price, firstFeedValue * secondFeedValue * 10 ** baseTokenDecimals / divider);
        assertTrue(price / 1e18 > 28000 && price / 1e18 < 30000, "price is expected (17*1651)");
        assertEq(price, 29550.9232441417986035e18, "price is expected");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_twoFeeds_InvertIdenticalProducesOne
    */
    function test_DIAOracle_quote_twoFeeds_InvertIdenticalProducesOne() public {
        string memory feed = "ETH/USD";
        uint256 divider = 1e3;

        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfigTwoFeeds({
            _firstFeed: feed,
            _secondFeed: feed,
            _divider: divider,
            _multiplier: 0,
            _invert: true
        });

        DIAOracleConfig oracleConfig = new DIAOracleConfig(cfg);
        DIAOracle oracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        oracle.initialize(oracleConfig, cfg.primaryKey, cfg.secondaryKey);

        assertEq(
            oracle.quote(1e18, address(tokens["RDPX"])), 10 ** (IERC20Metadata(cfg.baseToken).decimals()) / divider
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_ZeroPrice_oneFeed
    */
    function test_DIAOracle_quote_ZeroPrice_oneFeed() public {
        uint256 dividerToZeroPrice = 10 ** 36;
        IDIAOracle.DIADeploymentConfig memory cfgOneFeed = _defaultDIAConfig(dividerToZeroPrice, 0);
        DIAOracleConfig oracleConfigOneFeed = new DIAOracleConfig(cfgOneFeed);
        assertTrue(Strings.equal(cfgOneFeed.secondaryKey, ""), "Only one feed is used");

        DIAOracle oracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        oracle.initialize(oracleConfigOneFeed, cfgOneFeed.primaryKey, cfgOneFeed.secondaryKey);

        vm.expectRevert(IDIAOracle.ZeroQuote.selector);
        oracle.quote(1, address(tokens["RDPX"]));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_ZeroPrice_twoFeeds
    */
    function test_DIAOracle_quote_ZeroPrice_twoFeeds() public {
        uint256 dividerToZeroPrice = 10 ** 36;
        IDIAOracle.DIADeploymentConfig memory cfgTwoFeeds = _defaultDIAConfig(dividerToZeroPrice, 0);
        cfgTwoFeeds.secondaryKey = "ETH/USD";

        DIAOracleConfig oracleConfigTwoFeeds = new DIAOracleConfig(cfgTwoFeeds);
        DIAOracle oracle = DIAOracle(Clones.clone(address(new DIAOracle())));
        oracle.initialize(oracleConfigTwoFeeds, cfgTwoFeeds.primaryKey, cfgTwoFeeds.secondaryKey);

        vm.expectRevert(IDIAOracle.ZeroQuote.selector);
        oracle.quote(1, address(tokens["RDPX"]));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_AssetNotSupported
    */
    function test_DIAOracle_quote_AssetNotSupported() public {
        vm.expectRevert(IDIAOracle.AssetNotSupported.selector);
        DIA_ORACLE.quote(1e18, address(1));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracle_quote_AssetNotSupported
    */
    function test_DIAOracle_quote_BaseAmountOverflow() public {
        vm.expectRevert(IDIAOracle.BaseAmountOverflow.selector);
        DIA_ORACLE.quote(2 ** 128, address(tokens["RDPX"]));
    }

    function test_DIAOracle_quoteToken() public view {
        assertEq(address(DIA_ORACLE.quoteToken()), address(tokens["USDT"]), "must be USDC");
    }

    function test_DIAOracle_VERSION() public view {
        assertEq(DIA_ORACLE.VERSION(), "DIAOracle 4.0.0", "VERSION");
    }

    function test_DIAOracle_baseToken() public view {
        address baseTokenAddr = DIA_ORACLE.baseToken();
        assertEq(baseTokenAddr, address(tokens["RDPX"]), "baseToken");

        uint256 amount = 10 ** IERC20Metadata(baseTokenAddr).decimals();
        DIA_ORACLE.quote(amount, baseTokenAddr);
    }
}
