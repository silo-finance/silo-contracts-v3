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
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic4 --ffi -vvv
*/
contract LiquidationDebug_2025_10_15_Sonic4 is UserState {
    function setUp() public override {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 50725091);

        super.setUp();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_10_15_Sonic4 --ffi -vvv

    {
    "_flashLoanFrom": "0x2f5dc399b1e31f9808d1ef1256917abd2447c74f",
    "_debtAsset": "0xd3dce716f3ef535c5ff8d041c1a41c3bd89b97ae",
    "_maxDebtToCover": "237860",
    "_liquidation": {
        "collateralAsset": "0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38",
        "hook": "0x1abadd94dc049464144b84a981efbf35894126f4",
        "user": "0x451299a8943d72ec667f83f530b32992f8533140"
    },
    "_swapsInputs0x": [
        {
        "allowanceTarget": "0xac041df48df9791b0654f1dbbf2cc8450c5f2e9d",
        "sellToken": "0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38",
        "swapCallData": "0x83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad380001d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae07238508106a23cd0207bf07ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba30001cd806c9cd224a185724c54acf79e5593f479f55e0001f363c6d369888f5367e9f1ad7b6a7dae133e8740000000000301020300030101000102011eff00000000000000000000000000000000000000cd806c9cd224a185724c54acf79e5593f479f55e039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000"
        }
    ]
    }
    */
    function test_skip_debug_liquidation() public {
        address user = 0x451299a8943d72ec667f83f530B32992f8533140;
        ISilo flashLoanFrom = ISilo(0x2f5Dc399B1E31f9808D1EF1256917ABD2447c74f);
        vm.label(address(flashLoanFrom), "flashLoanFrom");
        SiloHookV1 hook = SiloHookV1(0x1AbaDD94Dc049464144b84A981EFbF35894126F4);
        vm.label(address(hook), "SiloHookV1");

        console2.log("Liquidation Debug 2025-10-15");

        ISiloConfig config = ISiloConfig(hook.siloConfig());

        (ISiloConfig.ConfigData memory collateralCfg, ISiloConfig.ConfigData memory debtCfg) =
            config.getConfigsForSolvency(user);

        assertEq(collateralCfg.token, address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38), "sanity collateral check with liquidation data"); 
        assertEq(debtCfg.token, address(0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE), "sanity debt check with liquidation data"); 

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
            swapCallData: hex"83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad380001d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae07238508106a23cd0207bf07ae1400013a5d6a7aab7c1b681892bdc3667c76a5e4116ba30001cd806c9cd224a185724c54acf79e5593f479f55e0001f363c6d369888f5367e9f1ad7b6a7dae133e8740000000000301020300030101000102011eff00000000000000000000000000000000000000cd806c9cd224a185724c54acf79e5593f479f55e039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000"
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
}
