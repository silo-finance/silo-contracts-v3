// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC4626OracleFactoryDeploy} from "silo-oracles/deploy/erc4626/ERC4626OracleFactoryDeploy.sol";
import {ERC4626OracleFactory} from "silo-oracles/contracts/erc4626/ERC4626OracleFactory.sol";
import {IERC4626OracleFactory} from "silo-oracles/contracts/interfaces/IERC4626OracleFactory.sol";
import {ERC4626Oracle} from "silo-oracles/contracts/erc4626/ERC4626Oracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

// FOUNDRY_PROFILE=oracles forge test --mc ERC4626OracleTest
contract ERC4626OracleTest is Test {
    IERC4626OracleFactory internal _factory;

    address internal _wosVault = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;

    function setUp() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_SONIC"))), 5685582);

        ERC4626OracleFactoryDeploy factoryDeploy = new ERC4626OracleFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();

        _factory = IERC4626OracleFactory(factoryDeploy.run());
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_createERC4626Oracle -vvv
    function test_ERC4626Oracle_createERC4626Oracle() public {
        IERC4626 vault = IERC4626(_wosVault);

        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));

        assertTrue(ERC4626OracleFactory(address(_factory)).createdInFactory(address(oracle)));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_quote -vvv
    function test_ERC4626Oracle_quote() public {
        IERC4626 vault = IERC4626(_wosVault);

        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));

        uint256 quote = oracle.quote(1 ether, address(vault));

        assertEq(quote, vault.convertToAssets(1 ether));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_quote_wrongBaseToken -vvv
    function test_ERC4626Oracle_quote_wrongBaseToken() public {
        IERC4626 vault = IERC4626(_wosVault);

        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));

        vm.expectRevert(ERC4626Oracle.AssetNotSupported.selector);
        oracle.quote(1 ether, address(1));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_quote_revertsZeroPrice -vvv
    function test_ERC4626Oracle_quote_revertsZeroPrice() public {
        IERC4626 vault = IERC4626(_wosVault);
        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));

        vm.expectRevert(ERC4626Oracle.ZeroPrice.selector);
        oracle.quote(0, address(vault));

        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.convertToAssets.selector), abi.encode(0));

        vm.expectRevert(ERC4626Oracle.ZeroPrice.selector);
        oracle.quote(1 ether, address(vault));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_quoteToken -vvv
    function test_ERC4626Oracle_quoteToken() public {
        IERC4626 vault = IERC4626(_wosVault);

        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));

        assertEq(oracle.quoteToken(), address(vault.asset()));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_beforeQuote -vvv
    function test_ERC4626Oracle_beforeQuote() public {
        IERC4626 vault = IERC4626(_wosVault);

        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));

        // should not revert
        oracle.beforeQuote(address(vault));
        oracle.beforeQuote(address(1));
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_VERSION -vvv
    function test_ERC4626Oracle_VERSION() public {
        IERC4626 vault = IERC4626(_wosVault);
        ISiloOracle oracle = _factory.createERC4626Oracle(vault, bytes32(0));
        assertEq(ERC4626Oracle(address(oracle)).VERSION(), "ERC4626Oracle 4.0.0", "VERSION");
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_baseToken -vvv
    function test_ERC4626Oracle_baseToken() public {
        IERC4626 vault = IERC4626(_wosVault);
        ERC4626Oracle oracle = ERC4626Oracle(address(_factory.createERC4626Oracle(vault, bytes32(0))));
        address baseTokenAddr = oracle.baseToken();
        assertEq(baseTokenAddr, address(vault), "baseToken");

        uint256 amount = 10 ** IERC20Metadata(baseTokenAddr).decimals();
        oracle.quote(amount, baseTokenAddr);
    }

    // FOUNDRY_PROFILE=oracles forge test --mt test_ERC4626Oracle_reorg
    function test_ERC4626Oracle_reorg() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");

        uint256 snapshot = vm.snapshotState();

        vm.prank(eoa1);
        ISiloOracle oracle1 = _factory.createERC4626Oracle(IERC4626(_wosVault), bytes32(0));

        vm.revertToState(snapshot);

        vm.prank(eoa2);
        ISiloOracle oracle2 = _factory.createERC4626Oracle(IERC4626(_wosVault), bytes32(0));

        assertNotEq(address(oracle1), address(oracle2), "oracle1 == oracle2");
    }
}
