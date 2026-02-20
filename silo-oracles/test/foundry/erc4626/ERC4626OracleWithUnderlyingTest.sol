// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {ERC4626OracleWithUnderlyingFactoryDeploy} from
    "../../../deploy/erc4626/ERC4626OracleWithUnderlyingFactoryDeploy.s.sol";
import {ERC4626OracleWithUnderlyingDeploy} from "../../../deploy/erc4626/ERC4626OracleWithUnderlyingDeploy.s.sol";
import {ERC4626OracleWithUnderlyingFactory} from
    "silo-oracles/contracts/erc4626/ERC4626OracleWithUnderlyingFactory.sol";
import {ERC4626OracleWithUnderlying} from "silo-oracles/contracts/erc4626/ERC4626OracleWithUnderlying.sol";
import {SiloOraclesFactoriesContracts} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626OracleWithUnderlying} from "silo-oracles/contracts/interfaces/IERC4626OracleWithUnderlying.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc ERC4626OracleWithUnderlyingTest --ffi -vv
*/
contract ERC4626OracleWithUnderlyingTest is Test {
    ERC4626OracleWithUnderlying oracle;
    address wstUSR;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 22724590); // forking Jun 17 2025

        AddrLib.init();

        ERC4626OracleWithUnderlyingFactoryDeploy factoryDeployer = new ERC4626OracleWithUnderlyingFactoryDeploy();
        factoryDeployer.disableDeploymentsSync();

        ERC4626OracleWithUnderlyingFactory factory = ERC4626OracleWithUnderlyingFactory(factoryDeployer.run());

        AddrLib.setAddress(SiloOraclesFactoriesContracts.ERC4626_ORACLE_UNDERLYING_FACTORY, address(factory));

        ERC4626OracleWithUnderlyingDeploy deployer = new ERC4626OracleWithUnderlyingDeploy();
        deployer.setUseConfig("wstUSR", "CHAINLINK_USR_USD");

        oracle = deployer.run();

        wstUSR = AddrLib.getAddress("wstUSR");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrappedVault_deploy --ffi -vv
     */
    function test_wrappedVault_deploy() public {
        // deploy pass
    }

    function test_ERC4626OracleWithUnderlying_VERSION() public view {
        assertEq(oracle.VERSION(), "ERC4626OracleWithUnderlying 4.0.0", "VERSION");
    }

    function test_ERC4626OracleWithUnderlying_baseToken() public view {
        address baseTokenAddr = oracle.baseToken();
        assertEq(baseTokenAddr, wstUSR, "baseToken");

        uint256 amount = 10 ** IERC20Metadata(baseTokenAddr).decimals();
        oracle.quote(amount, baseTokenAddr);
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrappedVault_price --ffi -vv
     */
    function test_wrappedVault_price() public {
        /*
        WstUSR::convertToAssets(1e18) = 1087372222978808737;
        at this block USR price in aggregator is 1.0
        chainlink.quote() => 1087372222978808737
        */
        assertEq(oracle.quote(1e18, AddrLib.getAddress("wstUSR")), 1.088293604071978577e18, "wstUSR price in USD");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrappedVault_BaseAmountOverflow --ffi -vv
     */
    function test_wrappedVault_BaseAmountOverflow() public {
        vm.expectRevert(IERC4626OracleWithUnderlying.BaseAmountOverflow.selector);
        oracle.quote(2 ** 128, address(1));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrappedVault_AssetNotSupported --ffi -vv
     */
    function test_wrappedVault_AssetNotSupported() public {
        vm.expectRevert(IERC4626OracleWithUnderlying.AssetNotSupported.selector);
        oracle.quote(1, address(1));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_wrappedVault_ZeroQuote --ffi -vv
     */
    function test_wrappedVault_ZeroQuote() public {
        vm.expectRevert(IERC4626OracleWithUnderlying.ZeroQuote.selector);
        oracle.quote(0, wstUSR);
    }
}
