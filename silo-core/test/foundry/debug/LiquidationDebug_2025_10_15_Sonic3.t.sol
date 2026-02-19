// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {UserState} from "./UserState.sol";


import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloHookV1} from "silo-core/contracts/hooks/SiloHookV1.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic3 --ffi -vvv
*/
contract LiquidationDebug_2025_10_15_Sonic3 is UserState {
    function setUp() public override {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 50726224);

        super.setUp();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic3 --ffi -vvv

    {
    "_flashLoanFrom": "0x322e1d5384aa4ed66aeca770b95686271de61dc3",
    "_debtAsset": "0x29219dd400f2bf60e5a23d13be72b486d4038894",
    "_maxDebtToCover": "105290",
    "_liquidation": {
        "collateralAsset": "0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38",
        "hook": "0xb01e62ba9bec9cfa24b2ee321392b8ce726d2a09",
        "user": "0x57af2d108b0a4b6e1298429bb7b4b6e1e5983620"
    },
    "_swapsInputs0x": [
        {
        "allowanceTarget": "0xac041df48df9791b0654f1dbbf2cc8450c5f2e9d",
        "sellToken": "0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38",
        "swapCallData": "0x83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000129219dd400f2bf60e5a23d13be72b486d40388940703871eaef0422001c407ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba300000001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000003010204002101010102030000ff00000000000000000000000000000000000000b48d7326e5ca4159f8f07b051bd3c72912049e11039e2fb66102314ce7b64ce5ce3e5183bc94ad3829219dd400f2bf60e5a23d13be72b486d403889400000000"
        }
    ]
    }
    */
    function test_skip_debug_liquidation() public {
        address user = 0x57Af2D108B0A4B6E1298429Bb7B4b6e1E5983620;
        ISilo flashLoanFrom = ISilo(0x322e1d5384aa4ED66AeCa770B95686271de61dc3);
        vm.label(address(flashLoanFrom), "flashLoanFrom");
        SiloHookV1 hook = SiloHookV1(0xB01e62Ba9BEc9Cfa24b2Ee321392b8Ce726D2A09);
        vm.label(address(hook), "SiloHookV1");

        console2.log("Liquidation Debug 2025-10-15");

        ISiloConfig config = ISiloConfig(hook.siloConfig());

        (ISiloConfig.ConfigData memory collateralCfg, ISiloConfig.ConfigData memory debtCfg) =
            config.getConfigsForSolvency(user);

        assertEq(collateralCfg.token, address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38), "sanity collateral check with liquidation data"); 
        assertEq(debtCfg.token, address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894), "sanity debt check with liquidation data"); 

        _printUserState(user, config);

        ILiquidationHelper.LiquidationData memory liquidation = ILiquidationHelper.LiquidationData({
            hook: IPartialLiquidation(collateralCfg.hookReceiver),
            collateralAsset: collateralCfg.token,
            user: user
        });

        ILiquidationHelper.DexSwapInput[] memory dexSwapInput = new ILiquidationHelper.DexSwapInput[](1);
        dexSwapInput[0] = ILiquidationHelper.DexSwapInput({
            sellToken: collateralCfg.token,
            allowanceTarget: SWAP_ALLOWANCE_HOLDER,
            swapCallData: hex"83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000129219dd400f2bf60e5a23d13be72b486d40388940703871eaef0422001c407ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba300000001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000003010204002101010102030000ff00000000000000000000000000000000000000b48d7326e5ca4159f8f07b051bd3c72912049e11039e2fb66102314ce7b64ce5ce3e5183bc94ad3829219dd400f2bf60e5a23d13be72b486d403889400000000"
        });

        // while (!ISilo(debtCfg.silo).isSolvent(user)) {
        //     console2.log("block number: ", block.number);
        //     vm.createSelectFork(vm.envString("RPC_SONIC"), block.number + 1);
        // }

        vm.prank(0x0665609124CC2a958Cf0ED582eE132076243B6Da);
        HELPER.executeLiquidation({
            _flashLoanFrom: flashLoanFrom,
            _debtAsset: debtCfg.token,
            _maxDebtToCover: ISilo(debtCfg.silo).maxRepay(user),
            _liquidation: liquidation,
            _dexSwapInput: dexSwapInput
        });

        _printUserState(user, config);
    }
}
