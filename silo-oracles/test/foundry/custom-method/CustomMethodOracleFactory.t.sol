// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {CustomMethodOracleFactory} from "silo-oracles/contracts/custom-method/CustomMethodOracleFactory.sol";
import {ICustomMethodOracle} from "silo-oracles/contracts/interfaces/ICustomMethodOracle.sol";

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
    CustomMethodOracleFactory internal factory = new CustomMethodOracleFactory();
    MintableToken internal base = new MintableToken(6);
    MintableToken internal quote = new MintableToken(6);
    MockFeed internal feed = new MockFeed(2e8);

    function test_CustomMethodOracle_predict_matches_create() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");

        address predicted = factory.predictAddress(cfg, address(this), keccak256("salt"));
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

    function test_CustomMethodOracle_method_name_without_parens_canonical_signature_on_clone() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle o = factory.create(cfg, keccak256("p"));
        assertEq(o.methodSignature(), "readUint()");
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

    function test_CustomMethodOracle_getConfig_exposes_target_selector_signature() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("c"));

        assertEq(oracle.methodSignature(), "readUint()");
        ICustomMethodOracle.OracleConfig memory oc = oracle.getConfig();
        assertEq(oc.callSelector, bytes4(keccak256("readUint()")));
        assertEq(oc.target, address(feed));
    }

    function test_CustomMethodOracle_VERSION() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint");
        ICustomMethodOracle oracle = factory.create(cfg, keccak256("v"));
        assertEq(IVersioned(address(oracle)).VERSION(), "CustomMethodOracle 4.5.0");
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
        cfg.methodSignature = _sig;
        cfg.priceDecimals = 8;
    }
}
