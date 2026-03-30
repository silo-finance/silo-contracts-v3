// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";
import {ISupraSValueFeed} from "silo-oracles/contracts/interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "silo-oracles/contracts/interfaces/ISupraSValueOracle.sol";
import {SupraSValueOracleFactory} from "silo-oracles/contracts/supra/SupraSValueOracleFactory.sol";
import {SupraSValueOracleFactoryDeploy} from "silo-oracles/deploy/supra/SupraSValueOracleFactoryDeploy.s.sol";

contract MockSupraFeed is ISupraSValueFeed {
    bool public shouldRevert;
    mapping(uint256 => PriceFeed) public data;

    function setShouldRevert(bool _revert) external {
        shouldRevert = _revert;
    }

    function setData(uint256 _pairId, uint256 _round, uint256 _decimals, uint256 _time, uint256 _price) external {
        data[_pairId] = PriceFeed({round: _round, decimals: _decimals, time: _time, price: _price});
    }

    function getSvalue(uint256 _pairIndex) external view returns (PriceFeed memory) {
        if (shouldRevert) revert("mock revert");
        return data[_pairIndex];
    }
}

/*
    FOUNDRY_PROFILE=oracles forge test --match-contract SupraSValueOracleFactoryTest -vv
*/
contract SupraSValueOracleFactoryTest is Test {
    SupraSValueOracleFactory internal factory;
    MintableToken internal base = new MintableToken(6);
    MintableToken internal quote = new MintableToken(6);
    MockSupraFeed internal feed = new MockSupraFeed();
    uint256 internal constant PAIR_ID = 150;

    function setUp() public {
        feed.setData(PAIR_ID, 1, 8, block.timestamp, 2e8);

        SupraSValueOracleFactoryDeploy deployer = new SupraSValueOracleFactoryDeploy();
        deployer.disableDeploymentsSync();
        factory = SupraSValueOracleFactory(address(deployer.run()));
    }

    function test_SupraSValueOracle_predict_matches_create() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();

        address predicted = factory.predictAddress(address(this), keccak256("salt"));
        ISupraSValueOracle oracle = factory.create(cfg, keccak256("salt"));
        assertEq(address(oracle), predicted);
    }

    function test_SupraSValueOracle_each_create_new_oracle_same_config_distinct_address() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        bytes32 salt = keccak256("same");
        ISupraSValueOracle a = factory.create(cfg, salt);
        ISupraSValueOracle b = factory.create(cfg, salt);
        assertNotEq(address(a), address(b), "each create deploys a new clone (nonce advances)");
    }

    function test_SupraSValueOracle_quote_auto_normalization() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        ISupraSValueOracle oracle = factory.create(cfg, keccak256("x"));

        uint256 q = ISiloOracle(address(oracle)).quote(1e18, address(base));
        assertEq(q, 1e18 * 2e8 * 1e4, "expected quote with 18 decimals");
    }

    function test_SupraSValueOracle_quote_manual_normalization_fallback() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        cfg.useCustomNormalization = true;
        cfg.normalizationDivider = 0;
        cfg.normalizationMultiplier = 1e4;

        ISupraSValueOracle oracle = factory.create(cfg, keccak256("manual"));
        uint256 q = ISiloOracle(address(oracle)).quote(1e18, address(base));
        assertEq(q, 1e18 * 2e8 * 1e4, "manual normalization should match expected");
    }

    function test_SupraSValueOracle_zero_price_reverts_on_quote() public {
        feed.setData(PAIR_ID, 1, 8, block.timestamp, 0);

        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("z"));
        vm.expectRevert(ISupraSValueOracle.ZeroQuote.selector);
        ISiloOracle(address(oracle)).quote(1e18, address(base));
    }

    function test_SupraSValueOracle_old_price_does_not_revert() public {
        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("stale"));
        vm.warp(2 hours);
        feed.setData(PAIR_ID, 2, 8, block.timestamp - 1 hours, 2e8);

        uint256 q = ISiloOracle(address(oracle)).quote(1e18, address(base));
        assertEq(q, 1e18 * 2e8 * 1e4, "stale timestamp should be accepted when time is non-zero");
    }

    function test_SupraSValueOracle_zero_time_reverts() public {
        feed.setData(PAIR_ID, 1, 8, 0, 2e8);

        vm.expectRevert(ISupraSValueOracle.TimeStampZero.selector);
        factory.create(_cfg(), keccak256("zero-time"));
    }

    function test_SupraSValueOracle_BaseTokenDecimalsAbove18() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        cfg.baseToken = IERC20Metadata(address(new MintableToken(19)));

        vm.expectRevert(ISupraSValueOracle.BaseTokenDecimalsAbove18.selector);
        factory.create(cfg, keccak256("too-many-decimals"));
    }

    function test_SupraSValueOracle_getConfig_exposes_fields() public {
        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("c"));
        ISupraSValueOracle.OracleConfig memory oc = oracle.getConfig();

        assertEq(oc.pairId, PAIR_ID);
        assertEq(oc.supraFeed, address(feed));
        assertEq(oc.baseToken, address(base));
        assertEq(oc.quoteToken, address(quote));
        assertEq(oc.priceDecimals, 8);
    }

    function test_SupraSValueOracle_VERSION() public {
        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("v"));
        assertEq(IVersioned(address(oracle)).VERSION(), "SupraSValueOracle 4.7.0");
    }

    function test_SupraSValueOracle_readPrice() public {
        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("v"));
        assertEq(oracle.readPrice(), 2e8, "direct read should match feed");
    }

    function test_SupraSValueOracle_baseToken() public {
        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("v"));
        assertEq(Aggregator(address(oracle)).baseToken(), address(base), "baseToken should match the base token");
    }

    function test_SupraSValueOracle_beforeQuote() public {
        ISupraSValueOracle oracle = factory.create(_cfg(), keccak256("v"));
        ISiloOracle(address(oracle)).beforeQuote(address(0));
    }

    function test_SupraSValueOracle_verifyConfig() public {
        ISupraSValueOracle.DeploymentConfig memory cfg;

        vm.expectRevert(ISupraSValueOracle.AddressZero.selector);
        factory.verifyConfig(cfg);

        cfg.baseToken = IERC20Metadata(address(base));
        vm.expectRevert(ISupraSValueOracle.AddressZero.selector);
        factory.verifyConfig(cfg);

        cfg.quoteToken = IERC20Metadata(address(base));
        vm.expectRevert(ISupraSValueOracle.AddressZero.selector);
        factory.verifyConfig(cfg);

        cfg.supraFeed = address(feed);
        vm.expectRevert(ISupraSValueOracle.TokensAreTheSame.selector);
        factory.verifyConfig(cfg);

        cfg.quoteToken = IERC20Metadata(address(quote));
        vm.expectRevert(ISupraSValueOracle.PairIdMustBeNonZero.selector);
        factory.verifyConfig(cfg);

        cfg.pairId = PAIR_ID;
        factory.verifyConfig(cfg);
    }

    function test_SupraSValueOracle_verifyConfig_fallback_decimals_when_feed_reverts() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        feed.setShouldRevert(true);

        vm.expectRevert(ISupraSValueOracle.PriceReadFailed.selector);
        factory.verifyConfig(cfg);

        cfg.fallbackPriceDecimals = 8;
        (uint256 divider, uint256 multiplier, uint8 priceDecimals) = factory.verifyConfig(cfg);

        assertEq(priceDecimals, 8);
        assertEq(divider, 0);
        assertEq(multiplier, 1e4);
    }

    function test_SupraSValueOracle_verifyConfig_invalid_manual_normalization() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        cfg.useCustomNormalization = true;
        cfg.normalizationDivider = 0;
        cfg.normalizationMultiplier = 0;

        vm.expectRevert(ISupraSValueOracle.InvalidNormalization.selector);
        factory.verifyConfig(cfg);
    }

    function _cfg() internal view returns (ISupraSValueOracle.DeploymentConfig memory cfg) {
        cfg.baseToken = base;
        cfg.quoteToken = quote;
        cfg.supraFeed = address(feed);
        cfg.pairId = PAIR_ID;
    }
}
