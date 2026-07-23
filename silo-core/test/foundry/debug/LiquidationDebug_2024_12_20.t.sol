// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";

import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

// FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2024_12_20 --ffi -vvv
contract LiquidationDebug_2024_12_20 is IntegrationTest {
    address internal constant _SILO_ADDR = 0x7abd3124E1e2F5f8aBF8b862d086647A5141bf4c;
    address internal constant EXECUTOR = 0xDaE3B7D951621b6600A88234246858e741AA70BB;
    IPartialLiquidation internal constant HOOK = IPartialLiquidation(0x2D2628f0434a5ed57601f6506d492849260193bA);
    // ILiquidationHelper constant internal helper = ILiquidationHelper(0xd98C025cf5d405FE3385be8C9BE64b219EC750F8);
    LiquidationHelper internal helper;

    function setUp() public {
        vm.label(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, "WETH");
        vm.label(address(HOOK), "IPartialLiquidation");

        vm.createSelectFork(getChainRpcUrl(ARBITRUM_ONE_ALIAS), 286812225);

        helper = new LiquidationHelper({
            _nativeToken: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            _exchangeProxy: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            _tokensReceiver: payable(0x865A1DA42d512d8854c7b0599c962F67F5A5A9d9)
        });
        helper.grantRole({role: helper.ALLOWED_ROLE(), account: EXECUTOR});

        vm.label(address(helper), "LiquidationHelper");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc LiquidationDebug_2024_12_20 --mt test_debug_liquidation_20241220 --ffi -vvv
    3487244284551604
    1133332483347470

    10000000000000000 max flashloan
     3487187346931926 flashloan amount
     3487187346931926 repay
    3661544387306889824 redeem
     3661546714278521 transfer collateral

     3661546714278521 weth balance
      170872179999664
    */
    function test_debug_liquidation_20241220() public {
        ISilo flashLoanFrom = ISilo(0x4E513ec0f16004519Dd95C421d249adD7C59d656);
        vm.label(address(flashLoanFrom), "flashLoanFrom");

        ILiquidationHelper.LiquidationData memory liquidation = ILiquidationHelper.LiquidationData({
            hook: HOOK,
            collateralAsset: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            user: EXECUTOR
        });

        ILiquidationHelper.DexSwapInput[] memory dexSwapInput = new ILiquidationHelper.DexSwapInput[](0);

        vm.prank(EXECUTOR);
        // 1	_flashLoanFrom	address	0x4E513ec0f16004519Dd95C421d249adD7C59d656
        // 2	_debtAsset	address	0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
        // 3	_maxDebtToCover	uint256 3487187346931926
        // 3	_liquidation.hook	address	0x2D2628f0434a5ed57601f6506d492849260193bA
        // 3	_liquidation.collateralAsset	address	0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
        // 3	_liquidation.user	address	0xDaE3B7D951621b6600A88234246858e741AA70BB
        helper.executeLiquidation({
            _flashLoanFrom: flashLoanFrom,
            _debtAsset: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            _maxDebtToCover: 3487187346931926,
            _liquidation: liquidation,
            _swapsInputs0x: dexSwapInput
        });
    }
}
