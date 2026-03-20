// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ERC20} from "openzeppelin5/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {CustomMethodOracleFactory} from "silo-oracles/contracts/custom-method/CustomMethodOracleFactory.sol";
import {CustomMethodOracle} from "silo-oracles/contracts/custom-method/CustomMethodOracle.sol";
import {ICustomMethodOracle} from "silo-oracles/contracts/interfaces/ICustomMethodOracle.sol";

contract Base18 is ERC20 {
    constructor() ERC20("Base", "BASE") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract Quote6 is ERC20 {
    constructor() ERC20("Quote", "Q") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockFeed {
    uint256 public spotPrice;

    constructor(uint256 _spot) {
        spotPrice = _spot;
    }

    function readUint() external view returns (uint256) {
        return spotPrice;
    }

    function latestAnswer() external view returns (int256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(uint256(spotPrice));
    }
}

/*
    FOUNDRY_PROFILE=oracles forge test --match-contract CustomMethodOracleFactoryTest -vv
*/
contract CustomMethodOracleFactoryTest is Test {
    CustomMethodOracleFactory internal factory = new CustomMethodOracleFactory();
    Base18 internal base = new Base18();
    Quote6 internal quote = new Quote6();
    MockFeed internal feed = new MockFeed(2e8);

    function test_predict_matches_create() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint()", false);

        address predicted = factory.predictAddress(cfg, address(this), keccak256("salt"));
        CustomMethodOracle oracle = factory.create(cfg, keccak256("salt"));
        assertEq(address(oracle), predicted);
    }

    function test_deduplicate_same_config() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint()", false);
        CustomMethodOracle a = factory.create(cfg, keccak256("a"));
        CustomMethodOracle b = factory.create(cfg, keccak256("b"));
        assertEq(address(a), address(b));
    }

    function test_quote_uint() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint()", false);
        CustomMethodOracle oracle = factory.create(cfg, keccak256("x"));

        uint256 q = oracle.quote(1e18, address(base));
        assertEq(q, 1e18 * feed.spotPrice());
    }

    function test_quote_signed() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("latestAnswer()", true);
        CustomMethodOracle oracle = factory.create(cfg, keccak256("y"));

        uint256 q = oracle.quote(1e18, address(base));
        assertEq(q, 1e18 * feed.spotPrice());
    }

    function test_zero_uint_reverts() public {
        MockFeed zeroFeed = new MockFeed(0);

        ICustomMethodOracle.DeploymentConfig memory cfg = _cfgWithTarget("readUint()", false, address(zeroFeed));
        CustomMethodOracle oracle = factory.create(cfg, keccak256("z"));

        vm.expectRevert(ICustomMethodOracle.ZeroQuote.selector);
        oracle.quote(1e18, address(base));
    }

    function test_expose_signature_and_calldata() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint()", false);
        CustomMethodOracle oracle = factory.create(cfg, keccak256("c"));

        assertEq(oracle.methodSignature(), "readUint()");
        assertEq(oracle.callSelector(), bytes4(keccak256("readUint()")));
        assertEq(oracle.callData(), abi.encodeWithSelector(bytes4(keccak256("readUint()"))));
        assertEq(oracle.priceTarget(), address(feed));
    }

    function test_VERSION() public {
        ICustomMethodOracle.DeploymentConfig memory cfg = _cfg("readUint()", false);
        CustomMethodOracle oracle = factory.create(cfg, keccak256("v"));
        assertEq(oracle.VERSION(), "CustomMethodOracle 1.0.0");
    }

    function _cfg(string memory sig, bool signed) internal view returns (ICustomMethodOracle.DeploymentConfig memory cfg) {
        return _cfgWithTarget(sig, signed, address(feed));
    }

    function _cfgWithTarget(string memory sig, bool signed, address target)
        internal
        view
        returns (ICustomMethodOracle.DeploymentConfig memory cfg)
    {
        cfg.baseToken = base;
        cfg.quoteToken = quote;
        cfg.target = target;
        cfg.methodSignature = sig;
        cfg.normalizationDivider = 1;
        cfg.normalizationMultiplier = 0;
        cfg.returnIsSigned = signed;
    }
}
