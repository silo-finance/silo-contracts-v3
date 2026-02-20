// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_08_21 --ffi -vvv
*/
contract LiquidationDebug_2025_08_21 is IntegrationTest {
    SiloLens internal constant LENS = SiloLens(0xB95AD415b0fcE49f84FbD5B26b14ec7cf4822c69);
    // IPartialLiquidation constant internal hook = IPartialLiquidation(0xDdBa71380230a3a5ab7094d9c774A6C5852a0fFC);
    // ILiquidationHelper constant internal helper = ILiquidationHelper(0xd98C025cf5d405FE3385be8C9BE64b219EC750F8);
    ILiquidationHelper internal helper;
    address internal swapAllowanceHolder = 0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D;
    address internal weth = 0x4200000000000000000000000000000000000006;

    function setUp() public {
        vm.label(weth, "WETH");
        vm.label(address(helper), "LiquidationHelper");
        // vm.label(address(hook), "IPartialLiquidation");
        vm.label(swapAllowanceHolder, "SWAP AllowanceHolder");

        vm.createSelectFork(vm.envString("RPC_SONIC"), 43873559);

        helper = LiquidationHelper(payable(0xf363C6d369888F5367e9f1aD7b6a7dAe133e8740));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_08_21 --mt test_skip_liquidation_20250821 --ffi -vvv

    "silo": "0x396922EF30Cf012973343f7174db850c7D265278",
    "borrower": "0x318312055830e05fAe49D3b15b8b5fCa5593Ecc8",

    */
    function test_skip_liquidation_20250821() public {
        address user = 0x318312055830e05fAe49D3b15b8b5fCa5593Ecc8;
        ISilo flashLoanFrom = ISilo(0x396922EF30Cf012973343f7174db850c7D265278);
        ISilo silo = ISilo(0x396922EF30Cf012973343f7174db850c7D265278);
        vm.label(address(flashLoanFrom), "flashLoanFrom");

        console2.log("Liquidation Debug 2025-08-21");

        ISiloConfig config = ISiloConfig(silo.config());

        (ISiloConfig.ConfigData memory collateralCfg, ISiloConfig.ConfigData memory debtCfg) =
            config.getConfigsForSolvency(user);

        _printUserState(user, config);

        ILiquidationHelper.LiquidationData memory liquidation = ILiquidationHelper.LiquidationData({
            hook: IPartialLiquidation(collateralCfg.hookReceiver),
            collateralAsset: collateralCfg.token,
            user: user
        });

        ILiquidationHelper.DexSwapInput[] memory dexSwapInput = new ILiquidationHelper.DexSwapInput[](0);

        // while (!ISilo(debtCfg.silo).isSolvent(user)) {
        //     console2.log("block number: ", block.number);
        //     vm.createSelectFork(vm.envString("RPC_SONIC"), block.number + 1);
        // }

        vm.prank(0x0665609124CC2a958Cf0ED582eE132076243B6Da);
        helper.executeLiquidation({
            _flashLoanFrom: flashLoanFrom,
            _debtAsset: debtCfg.token,
            _maxDebtToCover: ISilo(debtCfg.silo).maxRepay(user),
            _liquidation: liquidation,
            _dexSwapInput: dexSwapInput
        });

        _printUserState(user, config);
    }

    function _printUserState(address _user, ISiloConfig _config) internal view {
        console2.log("--------------------------------");
        console2.log("block number: ", block.number);
        console2.log("block timestamp: ", block.timestamp);
        console2.log("user: ", _user);

        (ISiloConfig.ConfigData memory collateralCfg, ISiloConfig.ConfigData memory debtCfg) =
            _config.getConfigsForSolvency(_user);

        console2.log("collateral silo: ", collateralCfg.silo);
        console2.log("collateral asset: ", collateralCfg.token);
        console2.log("      debt silo: ", debtCfg.silo);
        console2.log("      debt asset: ", debtCfg.token);
        console2.log("collateral Liquidation Threshold: ", collateralCfg.lt);
        console2.log("      debt Liquidation Threshold: ", debtCfg.lt);
        console2.log("                        user LTV: ", LENS.getUserLTV(ISilo(debtCfg.silo), _user));
        console2.log("user solvent?: ", ISilo(debtCfg.silo).isSolvent(_user));
    }
}
