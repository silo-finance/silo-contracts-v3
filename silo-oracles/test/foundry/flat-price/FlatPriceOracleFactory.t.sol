// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";
import {FlatPriceOracle} from "silo-oracles/contracts/flat-price/FlatPriceOracle.sol";
import {FlatPriceOracleFactory} from "silo-oracles/contracts/flat-price/FlatPriceOracleFactory.sol";
import {IFlatPriceOracle} from "silo-oracles/contracts/interfaces/IFlatPriceOracle.sol";
import {IFlatPriceOracleFactory} from "silo-oracles/contracts/interfaces/IFlatPriceOracleFactory.sol";
import {FlatPriceOracleFactoryDeploy} from "silo-oracles/deploy/flat-price/FlatPriceOracleFactoryDeploy.s.sol";

/*
FOUNDRY_PROFILE=oracles forge test --match-contract FlatPriceOracleFactoryTest -vv
*/
contract FlatPriceOracleFactoryTest is Test {
    uint256 internal constant PRICE = 2e18;

    FlatPriceOracleFactory internal factory;
    MintableToken internal base = new MintableToken(18);
    MintableToken internal quote = new MintableToken(18);

    function setUp() public {
        FlatPriceOracleFactoryDeploy deployer = new FlatPriceOracleFactoryDeploy();
        deployer.disableDeploymentsSync();
        factory = FlatPriceOracleFactory(address(deployer.run()));
    }

    function test_FlatPriceOracle_create_marks_oracle_as_created() public {
        ISiloOracle oracle = _createOracle(PRICE);
        assertTrue(factory.createdInFactory(address(oracle)));
    }

    function test_FlatPriceOracle_quote() public {
        ISiloOracle oracle = _createOracle(PRICE);
        assertEq(oracle.quote(1e18, address(base)), PRICE);
        assertEq(oracle.quote(5e18, address(base)), 10e18);
    }

    function test_FlatPriceOracle_quote_non18BaseDecimals() public {
        MintableToken base6 = new MintableToken(6);
        ISiloOracle oracle = IFlatPriceOracleFactory(factory).create(PRICE, address(base6), address(quote), bytes32(0));

        assertEq(FlatPriceOracle(address(oracle)).normalizationDivider(), 1e6);
        assertEq(oracle.quote(1e6, address(base6)), PRICE);
        assertEq(oracle.quote(5e6, address(base6)), 10e18);
    }

    function test_FlatPriceOracle_quote_zeroAmount_reverts() public {
        ISiloOracle oracle = _createOracle(PRICE);
        vm.expectRevert(IFlatPriceOracle.ZeroPrice.selector);
        oracle.quote(0, address(base));
    }

    function test_FlatPriceOracle_quote_fuzz_nonZero(uint256 _baseAmount) public {
        ISiloOracle oracle = _createOracle(PRICE);
        _baseAmount = bound(_baseAmount, 1, type(uint256).max / PRICE);

        uint256 quoteAmount = oracle.quote(_baseAmount, address(base));
        assertGt(quoteAmount, 0, "quote must never be zero for positive base amount");
    }

    function test_FlatPriceOracle_quoteToken() public {
        ISiloOracle oracle = _createOracle(PRICE);
        assertEq(oracle.quoteToken(), address(quote));
    }

    function test_FlatPriceOracle_baseToken() public {
        ISiloOracle oracle = _createOracle(PRICE);
        assertEq(Aggregator(address(oracle)).baseToken(), address(base));
    }

    function test_FlatPriceOracle_decimals_is18() public {
        ISiloOracle oracle = _createOracle(PRICE);
        assertEq(Aggregator(address(oracle)).decimals(), 18);
    }

    function test_FlatPriceOracle_description_builds_from_symbols() public {
        ISiloOracle oracle = _createOracle(PRICE);

        vm.mockCall(address(base), abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("BASE"));
        vm.mockCall(address(quote), abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("QUOTE"));

        assertEq(Aggregator(address(oracle)).description(), "BASE / QUOTE");
    }

    function test_FlatPriceOracle_wrongBase_reverts() public {
        ISiloOracle oracle = _createOracle(PRICE);
        vm.expectRevert(IFlatPriceOracle.AssetNotSupported.selector);
        oracle.quote(1e18, address(123));
    }

    function test_FlatPriceOracle_beforeQuote() public {
        ISiloOracle oracle = _createOracle(PRICE);
        oracle.beforeQuote(address(base));
    }

    function test_FlatPriceOracle_VERSION() public {
        ISiloOracle oracle = _createOracle(PRICE);
        assertEq(IVersioned(address(oracle)).VERSION(), "FlatPriceOracle 4.12.0");
    }

    function test_FlatPriceOracle_initialize_reverts_on_zero_price() public {
        vm.expectRevert(IFlatPriceOracle.ZeroPrice.selector);
        _createOracle(0);
    }

    function test_FlatPriceOracle_initialize_reverts_on_zero_base() public {
        vm.expectRevert(IFlatPriceOracle.AddressZero.selector);
        IFlatPriceOracleFactory(factory).create(PRICE, address(0), address(quote), bytes32(0));
    }

    function test_FlatPriceOracle_initialize_reverts_on_zero_quote() public {
        vm.expectRevert(IFlatPriceOracle.AddressZero.selector);
        IFlatPriceOracleFactory(factory).create(PRICE, address(base), address(0), bytes32(0));
    }

    function test_FlatPriceOracle_initialize_reverts_on_same_tokens() public {
        vm.expectRevert(IFlatPriceOracle.TokensAreTheSame.selector);
        IFlatPriceOracleFactory(factory).create(PRICE, address(base), address(base), bytes32(0));
    }

    function _createOracle(uint256 _price) internal returns (ISiloOracle oracle) {
        oracle = IFlatPriceOracleFactory(factory).create(_price, address(base), address(quote), bytes32(0));
    }
}
