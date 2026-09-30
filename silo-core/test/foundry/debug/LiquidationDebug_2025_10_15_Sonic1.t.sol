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
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic1 --ffi -vvv
*/
contract LiquidationDebug_2025_10_15_Sonic1 is IntegrationTest {
    SiloLens internal constant LENS = SiloLens(0xB95AD415b0fcE49f84FbD5B26b14ec7cf4822c69);
    // IPartialLiquidation constant internal hook = IPartialLiquidation(0xDdBa71380230a3a5ab7094d9c774A6C5852a0fFC);
    // ILiquidationHelper constant internal helper = ILiquidationHelper(0xf363c6d369888f5367e9f1ad7b6a7dae133e8740);
    ILiquidationHelper internal helper;
    address internal swapAllowanceHolder = 0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D;
    address internal weth = 0x4200000000000000000000000000000000000006;

    function setUp() public {
        vm.label(weth, "WETH");
        vm.label(address(helper), "LiquidationHelper");
        // vm.label(address(hook), "IPartialLiquidation");
        vm.label(swapAllowanceHolder, "SWAP AllowanceHolder");

        vm.createSelectFork(vm.envString("RPC_SONIC"), 50736627);

        helper = LiquidationHelper(payable(0xf363C6d369888F5367e9f1aD7b6a7dAe133e8740));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15 --mt test_skip_liquidation_20250821 --ffi -vvv

    {
    "_flashLoanFrom": "0x322e1d5384aa4ed66aeca770b95686271de61dc3",
    "_debtAsset": "0x29219dd400f2bf60e5a23d13be72b486d4038894",
    "_maxDebtToCover": "8648705123",
    "_liquidation": {
    "collateralAsset": "0xc7990369da608c2f4903715e3bd22f2970536c29",
    "hook": "0x5fdb173166df8555fbfdc6296ff12712d03898a0",
    "user": "0xf841dce6360c938465f0e56c3b3bf2f2a2f538f3"
    },
    "_swapsInputs0x": [
    {
      "allowanceTarget": "0xac041df48df9791b0654f1dbbf2cc8450c5f2e9d",
      "sellToken": "0xc7990369da608c2f4903715e3bd22f2970536c29",
      "swapCallData": "0x83bd37f90001c7990369da608c2f4903715e3bd22f2970536c29000129219dd400f2bf60e5a23d13be72b486d40388940a01cdd8acfbfdb5274933040c3f4d6e07ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba300000001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000004010205002101010102030004ff000000000000000000000000000000000000003d71ad2852676f8a3644a37a2932e678c0b80cf3c7990369da608c2f4903715e3bd22f2970536c2929219dd400f2bf60e5a23d13be72b486d4038894f6f87073cf8929c206a77b0694619dc776f8988500000000000000000000000000000000"
    }
    ]
    }
    */
    function test_skip_liquidation_20250821() public {
        address user = 0xF841dcE6360C938465F0E56c3B3BF2F2A2F538F3;
        ISilo flashLoanFrom = ISilo(0x322e1d5384aa4ED66AeCa770B95686271de61dc3);
        ISilo silo = ISilo(0x61FFBEAd1d4DC9fFba35eb16FD6caDEe9B37b2Aa);
        vm.label(address(flashLoanFrom), "flashLoanFrom");

        console2.log("Liquidation Debug 2025-10-15");

        ISiloConfig config = ISiloConfig(silo.config());

        (ISiloConfig.ConfigData memory collateralCfg, ISiloConfig.ConfigData memory debtCfg) =
            config.getConfigsForSolvency(user);

        _printUserState(user, config);

        ILiquidationHelper.LiquidationData memory liquidation = ILiquidationHelper.LiquidationData({
            hook: IPartialLiquidation(collateralCfg.hookReceiver),
            collateralAsset: collateralCfg.token,
            user: user
        });

        ILiquidationHelper.DexSwapInput[] memory dexSwapInput = new ILiquidationHelper.DexSwapInput[](1);
        dexSwapInput[0] = ILiquidationHelper.DexSwapInput({
            sellToken: collateralCfg.token,
            allowanceTarget: swapAllowanceHolder,
            swapCallData: hex"83bd37f90001c7990369da608c2f4903715e3bd22f2970536c29000129219dd400f2bf60e5a23d13be72b486d40388940a01cdd8acfbfdb5274933040c3f4d6e07ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba300000001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000004010205002101010102030004ff000000000000000000000000000000000000003d71ad2852676f8a3644a37a2932e678c0b80cf3c7990369da608c2f4903715e3bd22f2970536c2929219dd400f2bf60e5a23d13be72b486d4038894f6f87073cf8929c206a77b0694619dc776f8988500000000000000000000000000000000"
        });

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

        IPartialLiquidation hook = IPartialLiquidation(collateralCfg.hookReceiver);
        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) = hook.maxLiquidation(_user);
        console2.log("[maxLiquidation] collateral to liquidate: ", collateralToLiquidate);
        console2.log("[maxLiquidation] debt to repay: ", debtToRepay);
        console2.log("[maxLiquidation] sToken required: ", sTokenRequired);
    }
}
