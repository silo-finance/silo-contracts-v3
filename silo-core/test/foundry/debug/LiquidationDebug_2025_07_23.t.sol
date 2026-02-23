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
FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_07_23 --ffi -vvv
*/
contract LiquidationDebug_2025_07_23 is IntegrationTest {
    SiloLens internal constant LENS = SiloLens(0xB95AD415b0fcE49f84FbD5B26b14ec7cf4822c69);
    IPartialLiquidation internal constant HOOK = IPartialLiquidation(0xDdBa71380230a3a5ab7094d9c774A6C5852a0fFC);
    // ILiquidationHelper constant internal helper = ILiquidationHelper(0xd98C025cf5d405FE3385be8C9BE64b219EC750F8);
    ILiquidationHelper internal helper;
    address internal swapAllowanceHolder = 0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D;
    address internal weth = 0x4200000000000000000000000000000000000006;

    function setUp() public {
        vm.label(weth, "WETH");
        vm.label(address(helper), "LiquidationHelper");
        vm.label(address(HOOK), "IPartialLiquidation");
        vm.label(swapAllowanceHolder, "SWAP AllowanceHolder");

        vm.createSelectFork(vm.envString("RPC_SONIC"), 39843039 - 5);
        //  -1: 649934417432853875
        //  -5:
        // -10: 649402322711757183

        helper = LiquidationHelper(payable(0xf363C6d369888F5367e9f1aD7b6a7dAe133e8740));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2025_07_23 --mt test_skip_liquidation_20250723 --ffi -vvv

    _flashLoanFrom	address
    0x322e1d5384aa4ED66AeCa770B95686271de61dc3
    2	_debtAsset	address
    0x29219dd400f2Bf60E5a23d13Be72B486D4038894
    3	_maxDebtToCover	uint256
    1760484
    3	_liquidation.hook	address
    0xDdBa71380230a3a5ab7094d9c774A6C5852a0fFC
    3	_liquidation.collateralAsset	address
    0x79bbF4508B1391af3A0F4B30bb5FC4aa9ab0E07C
    3	_liquidation.user	address
    0xE67D43cB12C16a3Da358B3705EA1B32A652f1221
    4	_swapsInputs0x.sellToken	address
    0x79bbF4508B1391af3A0F4B30bb5FC4aa9ab0E07C
    4	_swapsInputs0x.allowanceTarget	address
    0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D
    4	_swapsInputs0x.swapCallData	bytes
    0x83bd37f9000179bbf4508b1391af3a0f4b30bb5fc4aa9ab0e07c000129219dd400f2bf60e5a23d13be72b486d40388940809d7284eb250b236031d552407ae14000146a405160258f071b5db777e0965c98133ea03a300000001f363c6d369888f5367e9f1ad7b6a7dae133e8740000000000301020300060101010200ff0000000000000000000000000000000000000000006f7c5f531024216cd8156d0b4e271e0c92a8a4e679bbf4508b1391af3a0f4b30bb5fc4aa9ab0e07c000000000000000000000000000000000000000000000000

    */
    function test_skip_liquidation_20250723() public {
        address user = 0xE67D43cB12C16a3Da358B3705EA1B32A652f1221;
        ISilo flashLoanFrom = ISilo(0x322e1d5384aa4ED66AeCa770B95686271de61dc3);
        ISilo silo = ISilo(0xE453c128f9Fa860960913f40eF975B1Fe5621E9e);
        vm.label(address(flashLoanFrom), "flashLoanFrom");

        ILiquidationHelper.LiquidationData memory liquidation = ILiquidationHelper.LiquidationData({
            hook: HOOK,
            collateralAsset: 0x79bbF4508B1391af3A0F4B30bb5FC4aa9ab0E07C,
            user: user
        });

        ILiquidationHelper.DexSwapInput[] memory dexSwapInput = new ILiquidationHelper.DexSwapInput[](1);

        dexSwapInput[0] = ILiquidationHelper.DexSwapInput({
            sellToken: 0x79bbF4508B1391af3A0F4B30bb5FC4aa9ab0E07C,
            allowanceTarget: swapAllowanceHolder,
            swapCallData: hex"83bd37f9000179bbf4508b1391af3a0f4b30bb5fc4aa9ab0e07c000129219dd400f2bf60e5a23d13be72b486d40388940809d7284eb250b236031d552407ae14000146a405160258f071b5db777e0965c98133ea03a300000001f363c6d369888f5367e9f1ad7b6a7dae133e8740000000000301020300060101010200ff0000000000000000000000000000000000000000006f7c5f531024216cd8156d0b4e271e0c92a8a4e679bbf4508b1391af3a0f4b30bb5fc4aa9ab0e07c000000000000000000000000000000000000000000000000"
        });

        console2.log("Liquidation Debug 2025-07-23");
        console2.log("block number: ", block.number);
        console2.log("user: ", user);

        ISiloConfig config = ISiloConfig(silo.config());
        (ISiloConfig.ConfigData memory collateralCfg, ISiloConfig.ConfigData memory debtCfg) =
            config.getConfigsForSolvency(user);
        console2.log("collateral silo: ", collateralCfg.silo);
        console2.log("debt silo: ", debtCfg.silo);
        console2.log("collateral Liquidation Threshold: ", collateralCfg.lt);
        console2.log(".     debt Liquidation Threshold: ", debtCfg.lt);
        console2.log("                        user LTV: ", LENS.getUserLTV(silo, user));

        vm.prank(0x0665609124CC2a958Cf0ED582eE132076243B6Da);
        helper.executeLiquidation({
            _flashLoanFrom: flashLoanFrom,
            _debtAsset: 0x29219dd400f2Bf60E5a23d13Be72B486D4038894,
            _maxDebtToCover: 1760484,
            _liquidation: liquidation,
            _dexSwapInput: dexSwapInput
        });
    }
}
