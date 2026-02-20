// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";

import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {MintableToken} from "../../_common/MintableToken.sol";

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/*
AGGREGATOR=ODOS FOUNDRY_PROFILE=core_test forge test --ffi --mc LiquidationHelperOdosTest -vv
*/
contract LiquidationHelperOdosTest is SiloLittleHelper, IntegrationTest {
    using SafeCast for uint256;

    LiquidationHelper liquidationHelper;
    SiloLens lens;
    ISilo flashLoanFrom;
    address hookReceiver;

    address payable public constant REWARD_COLLECTOR = payable(address(123456789));

    function setUp() public {
        uint256 blockToFork = 56376270;
        vm.createSelectFork(vm.envString("RPC_SONIC"), blockToFork);

        SiloFixture siloFixture = new SiloFixture();

        AddrLib.init();

        SiloConfigOverride memory configOverride;
        configOverride.token0 = AddrLib.getAddress(AddrKey.stS);
        configOverride.token1 = AddrLib.getAddress(AddrKey.wS);
        configOverride.configName = "Silo_stS_S";

        (, silo0, silo1,,, hookReceiver) = siloFixture.deploy_local(configOverride);

        token0 = MintableToken(AddrLib.getAddress(AddrKey.stS));
        token1 = MintableToken(AddrLib.getAddress(AddrKey.wS));

        vm.label(address(token0), "wS");
        vm.label(address(token1), "stS");

        liquidationHelper = new LiquidationHelper(
            AddrLib.getAddress(AddrKey.wS), AddrLib.getAddress(AddrKey.ODOS_ROUTER), REWARD_COLLECTOR
        );

        lens = new SiloLens();

        // another deployment so we have silo for flashloan
        (,, flashLoanFrom,,,) = siloFixture.deploy_local(configOverride);
        vm.label(address(flashLoanFrom), "flashLoanFrom");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_odos_liquidationCall_partial -vv
    */
    function test_odos_liquidationCall_partial() public {
        _createPositionToliquidate();
        _mockOracleCall(false);

        address borrower = makeAddr("borrower");

        emit log_named_decimal_uint("getLtv", lens.getLtv(silo1, borrower), 16);

        assertFalse(silo1.isSolvent(borrower), "user should be insolvent");
        assertLt(lens.getLtv(silo1, borrower), 0.98e18, "we want healthy position");

        (, uint256 debtToRepay,) = IPartialLiquidation(hookReceiver).maxLiquidation(borrower);

        assertLt(debtToRepay, silo1.maxRepay(borrower), "we want partial liquidation");

        assertEq(REWARD_COLLECTOR.balance, 0, "empty wallet before liquidation");

        _executeLiquidation();

        vm.clearMockedCalls();

        assertLe(lens.getLtv(silo1, borrower), 0.95e18, "user should be partially liquidated");
        assertTrue(silo1.isSolvent(borrower), "user should be solvent");

        assertGt(REWARD_COLLECTOR.balance, 0, "got profit");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_odos_liquidationCall_full -vv
    */
    function test_odos_liquidationCall_full() public {
        _createPositionToliquidate();
        _mockOracleCall(true);

        address borrower = makeAddr("borrower");

        emit log_named_decimal_uint("getLtv", lens.getLtv(silo1, borrower), 16);

        assertFalse(silo1.isSolvent(borrower), "user should be insolvent");
        assertLt(lens.getLtv(silo1, borrower), 1e18, "we want healthy position");

        (, uint256 debtToRepay,) = IPartialLiquidation(hookReceiver).maxLiquidation(borrower);

        assertEq(debtToRepay, silo1.maxRepay(borrower), "we want FULL");

        assertEq(REWARD_COLLECTOR.balance, 0, "empty wallet before liquidation");

        _executeLiquidation();

        vm.clearMockedCalls();

        assertLe(lens.getLtv(silo1, borrower), 0.95e18, "user should be partially liquidated");
        assertTrue(silo1.isSolvent(borrower), "user should be solvent");

        assertGt(REWARD_COLLECTOR.balance, 0, "got profit");
    }

    function _executeLiquidation() internal {
        address borrower = makeAddr("borrower");

        (uint256 collateralToLiquidate,,) = IPartialLiquidation(hookReceiver).maxLiquidation(borrower);

        // note: this is swap data for stS => sW with 50% slippage allowance
        bytes memory swapCallData = abi.encodePacked(
            hex"83bd37f90001e5da20f15420ad15de0fa650600afc998bbe39550001039e2fb66102314ce7b64ce5ce3e5183bc94ad3809",
            collateralToLiquidate.toUint72(), // amount in
            hex"0902b7ffaaafdba980007fffff00019b99e9c620b2E2f09E0b9Fced8F679eEcF2653FE00000001",
            address(liquidationHelper), // seller address in swap data
            hex"000000000301020300060101010200ff000000000000000000000000000000000000000000de861c8fc9ab78fe00490c5a38813d26e2d09c95e5da20f15420ad15de0fa650600afc998bbe3955000000000000000000000000000000000000000000000000"
        );

        ILiquidationHelper.DexSwapInput[] memory swapsInputs0x = new ILiquidationHelper.DexSwapInput[](1);
        swapsInputs0x[0].sellToken = AddrLib.getAddress(AddrKey.stS);
        swapsInputs0x[0].allowanceTarget = AddrLib.getAddress(AddrKey.ODOS_ROUTER);
        swapsInputs0x[0].swapCallData = swapCallData;

        ILiquidationHelper.LiquidationData memory liquidation;
        liquidation.hook = IPartialLiquidation(hookReceiver);
        liquidation.collateralAsset = AddrLib.getAddress(AddrKey.stS);
        liquidation.user = borrower;

        liquidationHelper.executeLiquidation(
            flashLoanFrom, AddrLib.getAddress(AddrKey.wS), silo1.maxRepay(borrower), liquidation, swapsInputs0x
        );
    }

    function _mockOracleCall(bool _priceCrash) internal {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(0x65d0F14f7809CdC4f90c3978c753C4671b6B815b).latestRoundData();

        answer = _priceCrash ? answer * 9700001 / 10000000 : answer * 9995 / 10000;

        vm.mockCall(
            0xb4fe9028A4D4D8B3d00e52341F2BB0798860532C,
            abi.encodePacked(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
    }

    function _createPositionToliquidate() internal {
        // deposit wS, borrow WETH
        address borrower = makeAddr("borrower");
        address depositor = makeAddr("depositor");
        uint256 assets = 50e18;
        uint256 deposit = 37.5e18;

        deal(AddrLib.getAddress(AddrKey.stS), borrower, assets);
        deal(AddrLib.getAddress(AddrKey.wS), depositor, deposit);

        vm.startPrank(depositor);
        IERC20(AddrLib.getAddress(AddrKey.wS)).approve(address(silo1), deposit);
        silo1.deposit(deposit, depositor, ISilo.CollateralType.Collateral);
        vm.stopPrank();

        vm.startPrank(borrower);
        IERC20(AddrLib.getAddress(AddrKey.stS)).approve(address(silo0), assets);
        silo0.deposit(assets, borrower, ISilo.CollateralType.Collateral);

        emit log_named_decimal_uint("maxBorrow", silo1.maxBorrow(borrower), 18);

        silo1.borrow(silo1.maxBorrow(borrower), borrower, borrower);
        silo0.withdraw(silo0.maxWithdraw(borrower), borrower, borrower, ISilo.CollateralType.Collateral);
        vm.stopPrank();

        uint256 amountToRepay = silo1.maxRepay(borrower);
        amountToRepay += flashLoanFrom.flashFee(AddrLib.getAddress(AddrKey.wS), amountToRepay);
        emit log_named_decimal_uint("repay + flash fee", amountToRepay, 18);

        deal(AddrLib.getAddress(AddrKey.wS), depositor, amountToRepay);

        vm.startPrank(depositor);
        IERC20(AddrLib.getAddress(AddrKey.wS)).approve(address(flashLoanFrom), amountToRepay);
        flashLoanFrom.deposit(amountToRepay, depositor, ISilo.CollateralType.Collateral);
        vm.stopPrank();
    }
}
