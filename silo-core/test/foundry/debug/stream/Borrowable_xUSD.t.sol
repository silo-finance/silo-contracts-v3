// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {UserState} from "../UserState.sol";

import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloHookV1} from "silo-core/contracts/hooks/SiloHookV1.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {SiloVault} from "silo-vaults/contracts/SiloVault.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic4 --ffi -vvv
*/
contract Borrowable_xUSD is UserState {
    // SiloVault internal constant VAULT = SiloVault(0x2BA39e5388aC6C702Cb29AEA78d52aa66832f1ee);

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_borrowable_xUSD_mainnet --ffi -vvv
    */
    function test_skip_borrowable_xUSD_mainnet() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 23735714);

        _borrowable_xUSD_mainnet(0x2E3A8F2DD842910FF8a3c65D93B129806e500417, "MAINNET");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_borrowable_xUSD_sonic --ffi -vvv
    */
    function test_skip_borrowable_xUSD_sonic() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 53838420);

        _borrowable_xUSD_mainnet(0x172a687c397E315DBE56ED78aB347D7743D0D4fa, "SONIC");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_borrowable_xUSD_arbitrum --ffi -vvv
    */
    function test_skip_borrowable_xUSD_arbitrum() public {
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), 397182312);

        _borrowable_xUSD_mainnet(0xd8872677af7bf49D85352fc18c7C32F106f6Fc49, "ARBITRUM");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_borrowable_xUSD_avalanche --ffi -vvv
    */
    function test_skip_borrowable_xUSD_avalanche() public {
        vm.createSelectFork(vm.envString("RPC_AVALANCHE"), 71479672);

        _borrowable_xUSD_mainnet(0xc380E5250d9718f8d9116Bc9d787A0229044e2EB, "AVALANCHE");
    }

    function _borrowable_xUSD_mainnet(address _xUSDSilo, string memory _chain) internal {
        console2.log("check if we can borrow from: s% on %s", _xUSDSilo, _chain);
        console2.log("block number", block.number);

        ISilo xUSDsilo = ISilo(_xUSDSilo);
        ISiloConfig config = ISiloConfig(xUSDsilo.config());
        (address silo0, address silo1) = config.getSilos();
        ISilo collateralSilo = silo0 == address(xUSDsilo) ? ISilo(silo1) : ISilo(silo0);

        ISiloConfig.ConfigData memory collateralConfig = config.getConfig(address(collateralSilo));

        if (collateralConfig.maxLtv == 0) {
            console2.log("max LTV is 0, not borrowable");
            return;
        }

        uint256 xDecimals = IERC20Metadata(xUSDsilo.asset()).decimals();
        uint256 liquidity = xUSDsilo.getLiquidity();
        emit log_named_decimal_uint("liquidity", liquidity, xDecimals);

        if (liquidity == 0) {
            console2.log("no liquidity!");
            return;
        }

        IERC20Metadata collateral = IERC20Metadata(collateralSilo.asset());
        uint256 collateralDecimals = collateral.decimals();

        address user = address(this);

        uint256 collateralAmount = 10 ** collateralDecimals * 1000;
        deal(address(collateral), user, collateralAmount);

        assertGt(collateral.balanceOf(user), 0, "we need asset to deposit");

        collateral.approve(address(collateralSilo), collateralAmount);
        collateralSilo.deposit(collateralAmount, user, ISilo.CollateralType.Collateral);

        emit log_named_decimal_uint(
            string.concat("collateral deposited ", collateral.symbol()), collateralAmount, collateralDecimals
        );
        uint256 borrowable = xUSDsilo.maxBorrow(user);
        emit log_named_decimal_uint("estimate borrowable", borrowable, xDecimals);

        if (borrowable == 0) {
            console2.log("no borrowable!");
            return;
        }

        xUSDsilo.borrow(borrowable, user, user);

        emit log_named_uint("maxRepay", xUSDsilo.maxRepay(user));
    }
}
