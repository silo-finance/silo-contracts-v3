// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {CustomMethodOracleFactory} from "silo-oracles/contracts/custom-method/CustomMethodOracleFactory.sol";
import {ICustomMethodOracle} from "silo-oracles/contracts/interfaces/ICustomMethodOracle.sol";

import {
    CustomMethodOracleFactoryDeploy
} from "silo-oracles/deploy/custom-method/CustomMethodOracleFactoryDeploy.s.sol";

import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";

contract MockFeed {
    uint256 public spotPrice;

    constructor(uint256 _spot) {
        spotPrice = _spot;
    }

    function readUint() external view returns (uint256) {
        return spotPrice;
    }
}

/*
    FOUNDRY_PROFILE=oracles forge test --match-contract CustomMethodOracleFactoryTest -vv
*/
contract CustomMethodOracleFactoryTest is Test {
    CustomMethodOracleFactory internal factory;
    MintableToken internal base = new MintableToken(6);
    MintableToken internal quote = new MintableToken(6);
    MockFeed internal feed = new MockFeed(2e8);

    function setUp() public {
        CustomMethodOracleFactoryDeploy deployer = new CustomMethodOracleFactoryDeploy();
        deployer.disableDeploymentsSync();
        factory = CustomMethodOracleFactory(address(deployer.run()));
    }

    function test_CustomMethodOracle_predict_matches_create() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");

        address predicted = factory.predictAddress(address(this), keccak256("salt"));
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("salt"));
        assertEq(address(oracle), predicted);
    }

    function test_CustomMethodOracle_each_create_new_oracle_same_config_distinct_address() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        bytes32 salt = keccak256("same");
        ICustomMethodOracle a = factory.create(cfg, salt);
        ICustomMethodOracle b = factory.create(cfg, salt);
        assertNotEq(address(a), address(b), "each create deploys a new clone (nonce advances)");
    }

    function test_CustomMethodOracle_quote_uint() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("x"));

        uint256 q = ISiloOracle(address(oracle)).quote(1e18, address(base));
        assertEq(q, 1e18 * feed.spotPrice() * 1e4, "expected quote with 18 decimals");
    }

    function test_CustomMethodOracle_zero_uint_reverts() public {
        MockFeed zeroFeed = new MockFeed(0);

        ICustomMethodOracle.DeploymentConfig memory cfg = _cfgWithTarget("readUint", address(zeroFeed));

        vm.expectRevert(ICustomMethodOracle.ZeroQuote.selector);
        factory.create(cfg, keccak256("z"));
    }

    function test_CustomMethodOracle_BaseTokenDecimalsAbove18() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        cfg.baseToken = IERC20Metadata(address(new MintableToken(19)));

        vm.expectRevert(ICustomMethodOracle.BaseTokenDecimalsAbove18.selector);
        factory.create(cfg, keccak256("too-many-decimals"));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test -vv --ffi --mt test_CustomMethodOracle_StaticCallFailed
    */
    function test_CustomMethodOracle_StaticCallFailed() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfgWithTarget("readUint", address(this));

        vm.expectRevert(ICustomMethodOracle.StaticCallFailed.selector);
        factory.create(cfg, keccak256("invalid method"));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test -vv --ffi --mt test_CustomMethodOracle_InvalidReturnData
    */
    function test_CustomMethodOracle_InvalidReturnData() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfgWithTarget("readUint", address(this));

        // mock cll with invalid return data, length is not 32
        vm.mockCall(address(cfg.target), bytes4(keccak256("readUint()")), abi.encode("not a number"));

        vm.expectRevert(ICustomMethodOracle.InvalidReturnData.selector);
        factory.create(cfg, keccak256("InvalidReturnData"));
    }

    function test_CustomMethodOracle_getConfig_exposes_target_selector_signature() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("c"));

        ICustomMethodOracle.OracleConfig memory oc = oracle.getConfig();
        assertEq(oc.callSelector, bytes4(keccak256("readUint()")));
        assertEq(oc.target, address(feed));
    }

    function test_CustomMethodOracle_VERSION() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("v"));
        assertEq(IVersioned(address(oracle)).VERSION(), "CustomMethodOracle 4.5.0");
    }

    function test_CustomMethodOracle_setMethodSignature() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("v"));

        assertEq(oracle.methodSignature(), "", "methodSignature should be empty by default");

        vm.expectRevert(ICustomMethodOracle.InvalidMethodSignature.selector);
        oracle.setMethodSignature("readUint256()");

        oracle.setMethodSignature("readUint()");

        assertEq(oracle.methodSignature(), "readUint()");
    }

    function test_CustomMethodOracle_readPrice() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("v"));

        assertEq(oracle.readPrice(), feed.spotPrice(), "direct read price should match the feed price");
    }

    function test_CustomMethodOracle_baseToken() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("v"));

        assertEq(Aggregator(address(oracle)).baseToken(), address(base), "baseToken should match the base token");
    }

    function test_CustomMethodOracle_beforeQuote() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("v"));

        // just for coverage and make sure it exists
        ISiloOracle(address(oracle)).beforeQuote(address(0));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test -vv --ffi --mt test_CustomMethodOracle_verifyConfig
    */
    function test_CustomMethodOracle_verifyConfig() public {
        ICustomMethodOracle.DeploymentConfig memory cfg;

        vm.expectRevert(ICustomMethodOracle.AddressZero.selector);
        factory.verifyConfig(cfg);

        cfg.baseToken = IERC20Metadata(address(base));
        vm.expectRevert(ICustomMethodOracle.AddressZero.selector);
        factory.verifyConfig(cfg);

        cfg.quoteToken = IERC20Metadata(address(base));
        vm.expectRevert(ICustomMethodOracle.AddressZero.selector);
        factory.verifyConfig(cfg);

        cfg.target = address(feed);
        vm.expectRevert(ICustomMethodOracle.TokensAreTheSame.selector);
        factory.verifyConfig(cfg);

        cfg.quoteToken = IERC20Metadata(address(quote));
        vm.expectRevert(ICustomMethodOracle.EmptyCallSelector.selector);
        factory.verifyConfig(cfg);

        cfg.callSelector = bytes4(keccak256(abi.encodePacked("readUint()")));
        factory.verifyConfig(cfg);
    }

    function _cfg(string memory _sig) internal view returns (ICustomMethodOracle.DeploymentConfig memory cfg) {
        return _cfgWithTarget(_sig, address(feed));
    }

    function _cfgWithTarget(string memory _sig, address _target)
        internal
        view
        returns (ICustomMethodOracle.DeploymentConfig memory cfg)
    {
        cfg.baseToken = base;
        cfg.quoteToken = quote;
        cfg.target = _target;
        cfg.callSelector = bytes4(keccak256(abi.encodePacked(string.concat(_sig, "()"))));
        cfg.priceDecimals = 8;
    }
}
