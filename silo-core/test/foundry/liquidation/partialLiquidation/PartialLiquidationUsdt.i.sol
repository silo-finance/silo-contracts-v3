// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {IUSDT} from "../../_common/IUSDT.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";

contract PartialLiquidationUsdtTest is SiloLittleHelper, IntegrationTest {
    using SafeERC20 for IERC20;

    uint256 constant DEPOSIT_AMOUNT = 1e6;
    uint256 constant MAX_AMOUNT = 1000e6;

    address depositor = makeAddr("Depositor");
    address borrowerUsdt = makeAddr("BorrowerUSDT");
    address borrowerUsdc = makeAddr("BorrowerUSDC");

    IUSDT usdt;
    IERC20 usdc;
    SiloLens siloLens;

    ISilo siloUsdc;
    ISilo siloUsdt;

    ManualLiquidationHelper manualLiquidation;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 24498300);

        AddrLib.init();

        usdt = IUSDT(getAddress("USDT"));
        usdc = IERC20(getAddress("USDC"));

        SiloConfigOverride memory overrides;
        (overrides.token0, overrides.token1) = _getTokensAddresses();
        token0 = MintableToken(overrides.token0);
        token1 = MintableToken(overrides.token1);
        vm.label(address(token0), token0.symbol());
        vm.label(address(token1), token1.symbol());

        overrides.configName = SiloConfigsNames.SILO_MOCKED;

        SiloFixture siloFixture = new SiloFixture();

        (, silo0, silo1,,,) = siloFixture.deploy_local(overrides);

        siloLens = new SiloLens();
        manualLiquidation = new ManualLiquidationHelper(AddrLib.getAddress("WETH"), payable(address(this)));

        (siloUsdc, siloUsdt) = silo0.asset() == address(usdt) ? (silo1, silo0) : (silo0, silo1);
    }

    /*
    AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_usdt_usdt_liquidation
    */
    function test_usdt_usdt_liquidation() public {
        _dealTokens();

        _depositUsdt(depositor);
        _depositUsdc(depositor);

        _depositUsdt(borrowerUsdc);
        _depositUsdc(borrowerUsdt);

        _borrowFrom(siloUsdc, borrowerUsdc);
        emit log_named_decimal_uint("borrowerUsdc LTV", siloLens.getUserLTV(silo0, borrowerUsdc), 16);

        _borrowFrom(siloUsdt, borrowerUsdt);
        emit log_named_decimal_uint("borrowerUsdt LTV", siloLens.getUserLTV(silo1, borrowerUsdt), 16);

        vm.warp(block.timestamp + 300 days);

        emit log_named_decimal_uint("insolvent borrowerUsdc LTV", siloLens.getUserLTV(silo0, borrowerUsdc), 16);
        emit log_named_decimal_uint("insolvent borrowerUsdt LTV", siloLens.getUserLTV(silo1, borrowerUsdt), 16);

        assertFalse(silo0.isSolvent(borrowerUsdt), "Borrower USDT is still solvent");
        assertFalse(silo0.isSolvent(borrowerUsdc), "Borrower USDC is still solvent");

        usdt.approve(address(manualLiquidation), MAX_AMOUNT);
        usdc.approve(address(manualLiquidation), MAX_AMOUNT);

        manualLiquidation.executeLiquidation(siloUsdt, borrowerUsdt);
        emit log_named_decimal_uint("solvent borrowerUsdt LTV", siloLens.getUserLTV(silo1, borrowerUsdt), 16);

        manualLiquidation.executeLiquidation(siloUsdc, borrowerUsdc);
        emit log_named_decimal_uint("solvent borrowerUsdc LTV", siloLens.getUserLTV(silo0, borrowerUsdc), 16);

        vm.warp(block.timestamp + 3000 days);

        bool expctOnePartial;

        if (!silo0.isSolvent(borrowerUsdc)) {
            expctOnePartial = true;
            manualLiquidation.executeLiquidation(siloUsdc, borrowerUsdc);
            emit log_named_decimal_uint("final borrowerUsdc LTV", siloLens.getUserLTV(silo0, borrowerUsdc), 16);
        }

        if (!silo0.isSolvent(borrowerUsdt)) {
            expctOnePartial = true;
            manualLiquidation.executeLiquidation(siloUsdt, borrowerUsdt);
            emit log_named_decimal_uint("final borrowerUsdt LTV", siloLens.getUserLTV(silo1, borrowerUsdt), 16);
        }

        assertTrue(expctOnePartial, "expected one partial liquidation");
    }

    /*
    AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_safeIncreaseAllowance
    */
    function test_safeIncreaseAllowance() public {
        /*
        this line needs to be etstes for USDT:
        
        IERC20(debtConfig.token).safeIncreaseAllowance(debtConfig.silo, repayDebtAssets);
        */

        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 1);
        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 1);
        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 2);
        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 0);
        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 2);
        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 2);
        IERC20(address(usdt)).safeIncreaseAllowance(address(siloUsdt), 9);
    }

    function _dealTokens() internal {
        deal(address(token0), depositor, MAX_AMOUNT);
        deal(address(token0), borrowerUsdc, MAX_AMOUNT);
        deal(address(token0), borrowerUsdt, MAX_AMOUNT);
        deal(address(token0), address(this), MAX_AMOUNT);

        deal(address(token1), depositor, MAX_AMOUNT);
        deal(address(token1), borrowerUsdc, MAX_AMOUNT);
        deal(address(token1), borrowerUsdt, MAX_AMOUNT);
        deal(address(token1), address(this), MAX_AMOUNT);


        emit log_named_decimal_uint("depositor balance", token0.balanceOf(depositor), 6);
        emit log_named_decimal_uint("borrowerUsdc balance", token0.balanceOf(borrowerUsdc), 6);
        emit log_named_decimal_uint("borrowerUsdt balance", token0.balanceOf(borrowerUsdt), 6);

        emit log_named_decimal_uint("depositor balance", token1.balanceOf(depositor), 6);
        emit log_named_decimal_uint("borrowerUsdc balance", token1.balanceOf(borrowerUsdc), 6);
        emit log_named_decimal_uint("borrowerUsdt balance", token1.balanceOf(borrowerUsdt), 6);
    }

    function _depositUsdc(address _depositor) internal {
        vm.startPrank(_depositor);
        usdc.approve(address(siloUsdc), DEPOSIT_AMOUNT);
        siloUsdc.deposit(DEPOSIT_AMOUNT, _depositor);
        vm.stopPrank();
    }
    
    function _depositUsdt(address _depositor) internal {
        vm.startPrank(_depositor);
        usdt.approve(address(siloUsdt), DEPOSIT_AMOUNT);
        siloUsdt.deposit(DEPOSIT_AMOUNT, _depositor);
        vm.stopPrank();
    }

    function _borrowFrom(ISilo _debtSilo, address _borrower) internal {
        vm.startPrank(_borrower);

        ISilo collateralSilo = address(_debtSilo) == address(silo0) ? silo1 : silo0;

        uint256 maxBorrow = _debtSilo.maxBorrow(_borrower);
        console2.log("maxBorrow", maxBorrow);
        _debtSilo.borrow(maxBorrow, _borrower, _borrower);

        uint256 maxWithdraw = collateralSilo.maxWithdraw(_borrower);
        console2.log("maxWithdraw", maxWithdraw);
        collateralSilo.withdraw(maxWithdraw, _borrower, _borrower);
        vm.stopPrank();
    }

    function _getTokensAddresses() internal virtual returns (address tokenForSilo0, address tokenForSilo1) {
        return (getAddress("USDT"), getAddress("USDC"));
    }
}
