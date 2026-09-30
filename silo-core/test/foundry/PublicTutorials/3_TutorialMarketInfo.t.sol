// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ISilo, IERC4626} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC20Metadata} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {SiloLens, ISiloLens} from "silo-core/contracts/SiloLens.sol";

/*
    This tutorial will help you to read the market data from Silo protocol.

    $ forge test -vv --ffi --mc TutorialMarketInfo
*/
contract TutorialMarketInfo is Test {
    // wstETH Silo. There are multiple wstETH Silos exist. This and following addresses are examples.
    ISilo public constant SILO0 = ISilo(0x0f3E42679f6Cf6Ee00b7eAC7b1676CA044615402);
    // WETH Silo
    ISilo public constant SILO1 = ISilo(0x58A31D1f2Be10Bf2b48C6eCfFbb27D1f3194e547);
    // wstETH/WETH market config for both Silos
    ISiloConfig public constant SILO_CONFIG = ISiloConfig(0x02ED2727D2Dc29b24E5AC9A7d64f2597CFb74bAB);
    // helper to read the data from Silo protocol, you can get the latest address from V2 protocol deployments
    ISiloLens public SILO_LENS;
    // example user address
    address public constant EXAMPLE_USER = 0x6d228Fa4daD2163056A48Fc2186d716f5c65E89A;

    // Fork Arbitrum at specific block.
    function setUp() public {
        uint256 blockToFork = 270931754;
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), blockToFork);

        SILO_LENS = new SiloLens();
    }

    // Every market consists of two ERC4626 vaults unified by one setup represented by SiloConfig. In the following
    // example there are two vaults: wstETH vault and WETH vault. This test will show the relation between SiloConfig
    // and vaults (Silos) addresses.
    function test_getVaultAddresses() public view {
        (address silo0, address silo1) = SILO_CONFIG.getSilos();

        assertEq(silo0, address(SILO0), "Silo0 is the first Silo for wstETH/WETH market");
        assertEq(IERC20Metadata(IERC4626(silo0).asset()).symbol(), "wstETH", "Silo0 asset is wstETH");

        assertEq(silo1, address(SILO1), "Silo1 is the second Silo for wstETH/WETH market");
        assertEq(IERC20Metadata(IERC4626(silo1).asset()).symbol(), "WETH", "Silo1 asset is WETH");

        assertEq(address(SILO0.config()), address(SILO_CONFIG), "SiloConfig is a setup for wstETH Silo");
        assertEq(address(SILO1.config()), address(SILO_CONFIG), "SiloConfig is also a setup for WETH Silo");
    }

    // SiloConfig is a setup for silo0 and silo1. SiloConfig stores ConfigData, which is an individual setup of
    // each Silo. Interest rate models, LTs and oracles can be different for Silos in one market. For example,
    // wstETH/WETH market is represented by wstETH and WETH Silos. wstETH Silo can have kinked interest rate
    // model, WETH can have dynamic interest rate model. You can set 80% as LT for wstETH Silo on deployment and
    // 99% as LT for WETH Silo. Silo V2 is permissionless, anyone can deploy Silos with any market parameters.
    function test_getMarketParams() public view {
        ISiloConfig.ConfigData memory silo0Setup = SILO0.config().getConfig(address(SILO0));
        ISiloConfig.ConfigData memory silo1Setup = SILO0.config().getConfig(address(SILO1));

        // The following example shows the variables from wstETH Silo ConfigData in different use cases.
        // Specification for every market parameter can be found in ISiloConfig.
        assertEq(IERC20Metadata(silo0Setup.token).symbol(), "wstETH", "Token is Silo asset");
        assertEq(silo0Setup.token, SILO0.asset(), "Token is ERC4626.asset()");
        assertEq(silo0Setup.silo, address(SILO0), "Silo address from config is equal to Silo");

        assertTrue(silo0Setup.protectedShareToken != address(0), "ProtectedShareToken is not zero address");
        assertTrue(silo0Setup.collateralShareToken != address(0), "CollateralShareToken is not zero address");
        assertTrue(silo0Setup.debtShareToken != address(0), "DebtShareToken is not zero address");

        assertTrue(silo0Setup.daoFee > 0, "Dao fee is > 0");
        assertTrue(silo0Setup.deployerFee > 0, "Deployer fee is > 0");

        assertEq(
            silo0Setup.interestRateModel,
            silo1Setup.interestRateModel,
            "wstETH and WETH interest rate models are equal"
        );

        assertTrue(silo0Setup.solvencyOracle != address(0), "SolvencyOracle is not zero address");

        assertTrue(
            ISiloOracle(silo0Setup.solvencyOracle).quote(10 ** 18, 0x5979D7b546E38E414F7E9822514be443A4800529) > 0,
            "solvencyOracle can provide a price for wstETH"
        );

        assertTrue(silo0Setup.maxLtvOracle != address(0), "maxLtvOracle is not zero address");
        assertEq(silo0Setup.maxLtv, 92 * 10 ** 16, "MaxLtv is 92%");
        assertEq(silo0Setup.lt, 96 * 10 ** 16, "Lt is 96%");
        assertEq(silo0Setup.liquidationTargetLtv, 95 * 10 ** 16, "LiquidationTargetLtv is 95%");
        assertEq(silo0Setup.liquidationFee, 15 * 10 ** 15, "LiquidationFee is 1.5%");
        assertEq(silo0Setup.flashloanFee, 1 * 10 ** 15, "LiquidationFee is 1%");

        assertTrue(silo0Setup.hookReceiver != address(0), "HookReceiver is not zero address");
        assertFalse(silo0Setup.callBeforeQuote, "CallBeforeQuote is false");
    }
}
