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
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic2 --ffi -vvv
*/
contract LiquidationDebug_2025_10_15_Sonic2 is UserState {
    function setUp() public override {
      
        vm.createSelectFork(vm.envString("RPC_SONIC"), 50726224);

        super.setUp();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic2 --ffi -vvv

    {
    "_flashLoanFrom": "0x08c320a84a59c6f533e0dca655cf497594bca1f9",
    "_debtAsset": "0x50c42deacd8fc9773493ed674b675be577f2634b",
    "_maxDebtToCover": "5694450777723",
    "_liquidation": {
        "collateralAsset": "0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38",
        "hook": "0x96eaf45bda24ff78c2a7b1c9dcf3f57d885aec8a",
        "user": "0x8ecee8d6dca1960b23f7e829c40dfe8be8b5d312"
    },
    "_swapsInputs0x": [
        {
        "allowanceTarget": "0xac041df48df9791b0654f1dbbf2cc8450c5f2e9d",
        "sellToken": "0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38",
        "swapCallData": "0x83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000150c42deacd8fc9773493ed674b675be577f2634b07035bfdde9d24d9050aa1db1a5207ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba300011c7670b221fe2cf46e0fa47d0e0cef17dc76a0230001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000003010203000301010001020119ff000000000000000000000000000000000000001c7670b221fe2cf46e0fa47d0e0cef17dc76a023039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000"
        }
    ]
    }
    */
    function test_skip_debug_liquidation() public {
        address user = 0x8eCee8d6DcA1960B23f7e829c40dfe8BE8B5d312;
        ISilo flashLoanFrom = ISilo(0x08C320A84a59c6f533e0DcA655cf497594BCa1F9);
        vm.label(address(flashLoanFrom), "flashLoanFrom");
        SiloHookV1 hook = SiloHookV1(0x96eaF45Bda24FF78C2A7B1c9DCf3F57D885aeC8a);
        vm.label(address(hook), "SiloHookV1");

        console2.log("Liquidation Debug 2025-10-15");

        ISiloConfig config = ISiloConfig(hook.siloConfig());

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
            allowanceTarget: SWAP_ALLOWANCE_HOLDER,
            swapCallData: hex"83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000150c42deacd8fc9773493ed674b675be577f2634b07035bfdde9d24d9050aa1db1a5207ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba300011c7670b221fe2cf46e0fa47d0e0cef17dc76a0230001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000003010203000301010001020119ff000000000000000000000000000000000000001c7670b221fe2cf46e0fa47d0e0cef17dc76a023039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000"
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
