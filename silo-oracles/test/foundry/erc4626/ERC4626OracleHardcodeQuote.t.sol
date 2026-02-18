// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {ERC4626Oracle} from "silo-oracles/contracts/erc4626/ERC4626Oracle.sol";

import {ERC4626OracleHardcodeQuoteFactoryDeploy} from
    "silo-oracles/deploy/erc4626/ERC4626OracleHardcodeQuoteFactoryDeploy.sol";

import {ERC4626OracleHardcodeQuoteFactory} from "silo-oracles/contracts/erc4626/ERC4626OracleHardcodeQuoteFactory.sol";

import {IERC4626OracleHardcodeQuoteFactory} from
    "silo-oracles/contracts/interfaces/IERC4626OracleHardcodeQuoteFactory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

// FOUNDRY_PROFILE=oracles forge test --mc ERC4626OracleHardcodeQuoteTest
contract ERC4626OracleHardcodeQuoteTest is Test {
    IERC4626 vault = IERC4626(0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1);
    address quoteToken = address(12345);
    IERC4626OracleHardcodeQuoteFactory factory;
    ISiloOracle oracle;
    address underlyingAsset;

    function setUp() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_SONIC"))), 41707056);

        ERC4626OracleHardcodeQuoteFactoryDeploy factoryDeploy = new ERC4626OracleHardcodeQuoteFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();

        underlyingAsset = vault.asset();
        _mockRevertAssetFunction();
        factory = IERC4626OracleHardcodeQuoteFactory(factoryDeploy.run());
        oracle = factory.createERC4626Oracle(vault, quoteToken, bytes32(0));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_createERC4626Oracle -vvv
    function test_ERC4626OracleHardcodeQuote_createERC4626Oracle() public view {
        assertTrue(ERC4626OracleHardcodeQuoteFactory(address(factory)).createdInFactory(address(oracle)));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_quote -vvv
    function test_ERC4626OracleHardcodeQuote_quote() public view {
        uint256 quote = oracle.quote(1 ether, address(vault));
        assertEq(quote, vault.convertToAssets(1 ether));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_quote_wrongBaseToken -vvv
    function test_ERC4626OracleHardcodeQuote_quote_wrongBaseToken() public {
        vm.expectRevert(ERC4626Oracle.AssetNotSupported.selector);
        oracle.quote(1 ether, address(1));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_quote_revertsZeroPrice -vvv
    function test_ERC4626OracleHardcodeQuote_quote_revertsZeroPrice() public {
        vm.expectRevert(ERC4626Oracle.ZeroPrice.selector);
        oracle.quote(0, address(vault));

        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.convertToAssets.selector), abi.encode(0));

        vm.expectRevert(ERC4626Oracle.ZeroPrice.selector);
        oracle.quote(1 ether, address(vault));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_quoteToken -vvv
    function test_ERC4626OracleHardcodeQuote_quoteToken() public view {
        assertEq(oracle.quoteToken(), quoteToken);
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_beforeQuote -vvv
    function test_ERC4626OracleHardcodeQuote_beforeQuote() public {
        // should not revert
        oracle.beforeQuote(address(vault));
        oracle.beforeQuote(address(1));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626OracleHardcodeQuote_reorg
    function test_ERC4626OracleHardcodeQuote_reorg() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");

        uint256 snapshot = vm.snapshotState();

        vm.prank(eoa1);
        ISiloOracle oracle1 = factory.createERC4626Oracle(vault, quoteToken, bytes32(0));

        vm.revertToState(snapshot);

        vm.prank(eoa2);
        ISiloOracle oracle2 = factory.createERC4626Oracle(vault, quoteToken, bytes32(0));

        assertNotEq(address(oracle1), address(oracle2), "oracle1 == oracle2");
    }

    function _mockRevertAssetFunction() internal {
        vm.mockCallRevert(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), bytes("reason"));
    }
}
