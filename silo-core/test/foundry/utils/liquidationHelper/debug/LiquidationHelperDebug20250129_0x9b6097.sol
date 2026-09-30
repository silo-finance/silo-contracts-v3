// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";

/*
 FOUNDRY_PROFILE=core_test forge test --ffi --mc LiquidationHelperDebug20250129_0x9b6097 -vv

https://sonicscan.org/tx/0x9b6097274e9b9ee17c595b25c4d9fd6df3538a6a6ad9fc311b4371c98c9101f4

BAD DEBT SCENARIO

executeLiquidation(address, address, uint256, (address,address,address), (address,address,bytes)[])
#	Name	Type	Data
1	_flashLoanFrom	address	0x4E216C15697C1392fE59e1014B009505E05810Df
2	_debtAsset	address	0x29219dd400f2Bf60E5a23d13Be72B486D4038894
3	_maxDebtToCover	uint256
1061306
3	_liquidation.hook	address	0xB01e62Ba9BEc9Cfa24b2Ee321392b8Ce726D2A09
3	_liquidation.collateralAsset	address	0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38
3	_liquidation.user	address	0x748e6AC25025758612507CEFeeD7987Db2dBDd8b
4	_swapsInputs0x.sellToken	address	0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38
4	_swapsInputs0x.allowanceTarget	address	0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D
4	_swapsInputs0x.swapCallData	bytes
0x83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000129219dd400f2bf60e5a23d13be72b486d40388940822b0e56179485ffe0311617907ae1400019b99e9c620b2e2f09e0b9fced8f679eecf2653fe0001074f336508598b9d34e5fa0b6441b2dec1f309fe0001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000003010203000801010001020100ff00000000000000000000000000000000000000074f336508598b9d34e5fa0b6441b2dec1f309fe039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000


*/
contract LiquidationHelperDebug20250129_0x9b6097 is Test {
    address payable public constant REWARD_COLLECTOR = payable(address(123456789));
    SiloLens lens;

    function setUp() public {
        uint256 blockToFork = 5796163;
        vm.createSelectFork(vm.envString("RPC_SONIC"), blockToFork);

        lens = new SiloLens();
    }

    /*
         TODO this can must be skip because foundry do not support Sonic network yet
    */
    function test_skip_debug_liquidationCall() public {
        LiquidationHelper liquidationHelper = LiquidationHelper(payable(0xf363C6d369888F5367e9f1aD7b6a7dAe133e8740));

        //        liquidationHelper = new LiquidationHelper(
        //            0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38,
        //            0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D,
        //            payable(makeAddr("TOKENS_RECEIVER"))
        //        );

        address hookReceiver = 0xB01e62Ba9BEc9Cfa24b2Ee321392b8Ce726D2A09;
        address borrower = 0x748e6AC25025758612507CEFeeD7987Db2dBDd8b;

        ISilo flashLoanFrom = ISilo(0x4E216C15697C1392fE59e1014B009505E05810Df);
        PartialLiquidation liquidation = PartialLiquidation(hookReceiver);

        vm.label(address(liquidationHelper), "LiquidationHelper");
        ISiloConfig siloConfig = liquidation.siloConfig();
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(borrower);

        emit log_named_string("solvent?", ISilo(debtConfig.silo).isSolvent(borrower) ? "yes" : "NO");
        uint256 ltv = lens.getLtv(ISilo(debtConfig.silo), borrower);
        emit log_named_decimal_uint("getLtv", ltv, 16);
        emit log_named_address("user", borrower);
        emit log_named_address("silo", address(debtConfig.silo));

        (uint256 collateral, uint256 debtToRepay,) = liquidation.maxLiquidation(borrower);
        emit log_named_decimal_uint("max collateral", collateral, 18);
        emit log_named_decimal_uint("max debtToRepay", debtToRepay, 6);

        //        uint256 collateralToLiquidate = 639935999999999999491;
        /*

        83bd37f9
        0001039e2fb66102314ce7b64ce5ce3e5183bc94ad38
        000129219dd400f2bf60e5a23d13be72b486d4038894
        08
        22b1c8c12279fffe03
        1160f707ae1400019b99e9c620b2e2f09e0b9fced8f679eecf2653fe00000001
        f363c6d369888f5367e9f1ad7b6a7dae133e8740
        000000000301020300060101010201ff0000000000000000000000000000000000000000009f46dd8f2a4016c26c1cf1f4ef90e5e1928d756b039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000

        */
        bytes memory swapCallData = abi.encode(
            //            hex"83bd37f9",
            //            hex"0001039e2fb66102314ce7b64ce5ce3e5183bc94ad38", // sell token
            //            hex"000129219dd400f2bf60e5a23d13be72b486d4038894", // buy token
            //            hex"08",
            //            hex"22b1c8c12279fffe03", // amount in, 18 characters
            //            hex"1160f707ae1400019b99e9c620b2e2f09e0b9fced8f679eecf2653fe00000001",
            //            address(liquidationHelper), // seller address in swap data
            //            hex"000000000301020300060101010201ff0000000000000000000000000000000000000000009f46dd8f2a4016c26c1cf1f4ef90e5e1928d756b039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000"
            hex"83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000129219dd400f2bf60e5a23d13be72b486d40388940822b0e56179485ffe0311617907ae1400019b99e9c620b2e2f09e0b9fced8f679eecf2653fe0001074f336508598b9d34e5fa0b6441b2dec1f309fe0001f363c6d369888f5367e9f1ad7b6a7dae133e87400000000003010203000801010001020100ff00000000000000000000000000000000000000074f336508598b9d34e5fa0b6441b2dec1f309fe039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000"
        );

        ILiquidationHelper.DexSwapInput[] memory swapsInputs0x = new ILiquidationHelper.DexSwapInput[](1);
        swapsInputs0x[0].sellToken = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
        swapsInputs0x[0].allowanceTarget = 0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D;
        swapsInputs0x[0].swapCallData = swapCallData;

        vm.label(swapsInputs0x[0].allowanceTarget, "allowanceTarget");

        ILiquidationHelper.LiquidationData memory liquidationData;
        liquidationData.hook = IPartialLiquidation(hookReceiver);
        liquidationData.collateralAsset = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
        liquidationData.user = borrower;

        {
            address debtToken = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
            vm.label(debtToken, "debtToken");
            vm.label(liquidationData.collateralAsset, "collateralAsset");

            emit log_named_decimal_uint("collateralConfig.liquidationFee", collateralConfig.liquidationFee, 18);
            emit log_named_decimal_uint("==", (1e18 - collateralConfig.liquidationFee), 18);

            //            uint256 debtToCover = 1061306;
            //            uint256 debtToCover = debtToRepay * 0.95e18 / ltv;
            uint256 debtToCover = debtToRepay * (1e18 - collateralConfig.liquidationFee) / ltv;

            emit log_named_decimal_uint("calculated debtToCover", debtToCover, 6);

            liquidationHelper.executeLiquidation(
                flashLoanFrom, debtToken, debtToCover, liquidationData, swapsInputs0x
            );
        }
    }
}
