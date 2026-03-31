// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";
import {ISupraOraclePull_V2} from "silo-oracles/contracts/interfaces/ISupraOraclePull_V2.sol";
import {ISupraSValueFeed} from "silo-oracles/contracts/interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "silo-oracles/contracts/interfaces/ISupraSValueOracle.sol";
import {SupraSValueOracleFactory} from "silo-oracles/contracts/supra/SupraSValueOracleFactory.sol";

contract MockSupraFeed is ISupraSValueFeed {
    mapping(uint256 => PriceFeed) public data;

    function setData(uint256 _pairId, uint256 _round, uint256 _decimals, uint256 _time, uint256 _price) external {
        data[_pairId] = PriceFeed({round: _round, decimals: _decimals, time: _time, price: _price});
    }

    function getSvalue(uint256 _pairIndex) external view returns (PriceFeed memory) {
        return data[_pairIndex];
    }
}

contract MockSupraOraclePullV2 is ISupraOraclePull_V2 {
    address public feed;

    function setFeed(address _feed) external {
        feed = _feed;
    }

    function checkSupraSValueFeed() external view returns (address) {
        return feed;
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
    MockSupraOraclePullV2 internal oraclePull = new MockSupraOraclePullV2();
    uint256 internal constant PAIR_ID = 150;

    function setUp() public {
        feed.setData({_pairId: PAIR_ID, _round: 1, _decimals: 8, _time: block.timestamp, _price: 2e8});
        feed.setData({_pairId: 0, _round: 1, _decimals: 8, _time: block.timestamp, _price: 1e8});
        oraclePull.setFeed(address(feed));
        factory = new SupraSValueOracleFactory(ISupraOraclePull_V2(address(oraclePull)));
    }

    function test_SupraSValueOracle_constructor_reverts_on_zero_oracle_pull() public {
        vm.expectRevert(ISupraSValueOracle.AddressZero.selector);
        new SupraSValueOracleFactory(ISupraOraclePull_V2(address(0)));
    }

    function test_SupraSValueOracle_predict_matches_create() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();

        address predicted = factory.predictAddress({_deployer: address(this), _externalSalt: keccak256("salt")});
        ISupraSValueOracle oracle = factory.create({_config: cfg, _externalSalt: keccak256("salt")});
        assertEq(address(oracle), predicted);
    }

    function test_SupraSValueOracle_each_create_new_oracle_same_config_distinct_address() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        bytes32 salt = keccak256("same");
        ISupraSValueOracle a = factory.create({_config: cfg, _externalSalt: salt});
        ISupraSValueOracle b = factory.create({_config: cfg, _externalSalt: salt});
        assertNotEq(address(a), address(b), "each create deploys a new clone (nonce advances)");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_SupraSValueOracle_quote_auto_normalization -vv
    */
    function test_SupraSValueOracle_quote_auto_normalization() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        ISupraSValueOracle oracle = factory.create({_config: cfg, _externalSalt: keccak256("x")});

        uint256 q = ISiloOracle(address(oracle)).quote({_baseAmount: 1e18, _baseToken: address(base)});
        assertEq(q, 1e18 * 2e8 * 1e4, "expected quote with 18 decimals");
    }

    function test_SupraSValueOracle_zero_price_reverts_on_quote() public {
        feed.setData({_pairId: PAIR_ID, _round: 1, _decimals: 8, _time: block.timestamp, _price: 0});

        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("z")});
        vm.expectRevert(ISupraSValueOracle.ZeroQuote.selector);
        ISiloOracle(address(oracle)).quote({_baseAmount: 1e18, _baseToken: address(base)});
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_SupraSValueOracle_old_price_does_not_revert -vv
    */
    function test_SupraSValueOracle_old_price_does_not_revert() public {
        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("stale")});
        vm.warp(block.timestamp + 300 days);
        feed.setData({_pairId: PAIR_ID, _round: 2, _decimals: 8, _time: block.timestamp - 100 days, _price: 1e8});

        uint256 q = ISiloOracle(address(oracle)).quote({_baseAmount: 1e6, _baseToken: address(base)});
        assertEq(q, 1e6 * 1e8 * 1e4, "stale timestamp should be accepted when time is non-zero");
    }

    function test_SupraSValueOracle_zero_time_reverts() public {
        feed.setData({_pairId: PAIR_ID, _round: 1, _decimals: 8, _time: 0, _price: 2e8});

        vm.expectRevert(ISupraSValueOracle.TimeStampZero.selector);
        factory.create({_config: _cfg(), _externalSalt: keccak256("zero-time")});
    }

    function test_SupraSValueOracle_BaseTokenDecimalsAbove18() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        cfg.baseToken = IERC20Metadata(address(new MintableToken(19)));

        vm.expectRevert(ISupraSValueOracle.BaseTokenDecimalsAbove18.selector);
        factory.create({_config: cfg, _externalSalt: keccak256("too-many-decimals")});
    }

    function test_SupraSValueOracle_getConfig_exposes_fields() public {
        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("c")});
        ISupraSValueOracle.OracleConfig memory oc = oracle.getConfig();

        assertEq(oc.pairId, PAIR_ID);
        assertEq(address(oc.supraSValueFeed), address(feed));
        assertEq(oc.baseToken, address(base));
        assertEq(oc.quoteToken, address(quote));
    }

    function test_SupraSValueOracle_VERSION() public {
        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("v")});
        assertEq(IVersioned(address(oracle)).VERSION(), "SupraSValueOracle 4.7.0");
    }

    function test_SupraSValueOracle_readPrice() public {
        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("v")});
        assertEq(oracle.readPrice(), 2e8, "direct read should match feed");
    }

    function test_SupraSValueOracle_baseToken() public {
        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("v")});
        assertEq(Aggregator(address(oracle)).baseToken(), address(base), "baseToken should match the base token");
    }

    function test_SupraSValueOracle_beforeQuote() public {
        ISupraSValueOracle oracle = factory.create({_config: _cfg(), _externalSalt: keccak256("v")});
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
        vm.expectRevert(ISupraSValueOracle.TokensAreTheSame.selector);
        factory.verifyConfig(cfg);

        cfg.quoteToken = IERC20Metadata(address(quote));
        cfg.pairId = 0;
        factory.verifyConfig(cfg);

        cfg.pairId = PAIR_ID;
        (uint256 divider, uint256 multiplier, uint8 priceDecimals, ISupraSValueFeed supraFeed) = factory.verifyConfig(cfg);
        assertTrue(divider != 0 || multiplier != 0);
        assertEq(priceDecimals, 8);
        assertEq(address(supraFeed), address(feed));
    }

    function test_SupraSValueOracle_verifyConfig_missing_pair_data_reverts() public {
        ISupraSValueOracle.DeploymentConfig memory cfg = _cfg();
        cfg.pairId = 999999;
        vm.expectRevert(ISupraSValueOracle.TimeStampZero.selector);
        factory.verifyConfig(cfg);
    }

    function _cfg() internal view returns (ISupraSValueOracle.DeploymentConfig memory cfg) {
        cfg.baseToken = base;
        cfg.quoteToken = quote;
        cfg.pairId = PAIR_ID;
    }
}
