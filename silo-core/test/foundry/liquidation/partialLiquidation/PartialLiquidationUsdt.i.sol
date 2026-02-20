// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";

import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {IUSDT} from "../../_common/IUSDT.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

contract PartialLiquidationUsdtTest is SiloLittleHelper, IntegrationTest {
    address depositor = makeAddr("Depositor");
    address borrowerUsdt = makeAddr("BorrowerUSDT");
    address borrowerUsdc = makeAddr("BorrowerUSDC");

    IUSDT usdt;
    SiloLens siloLens;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 24498300);

        AddrLib.init();

        token0 = MintableToken(getAddress("USDT"));
        token1 = MintableToken(getAddress("USDC"));
        vm.label(address(token0), "USDT");
        vm.label(address(token1), "USDC");
        usdt = IUSDT(getAddress("USDT"));

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);

        overrides.configName = SiloConfigsNames.SILO_MOCKED;

        SiloFixture siloFixture = new SiloFixture();

        (, silo0, silo1,,,) = siloFixture.deploy_local(overrides);

        siloLens = new SiloLens();
    }

    /*
    AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_setup
    */
    function test_setup() public {
        _dealTokens();

        _depositUsdt(depositor);
        _depositTo(silo1, depositor);

        _depositUsdt(borrowerUsdc);
        _depositTo(silo1, borrowerUsdt);

        _borrowFrom(silo1, borrowerUsdc);
        emit log_named_decimal_uint("borrowerUsdc LTV", siloLens.getUserLTV(silo0, borrowerUsdc), 16);

        _borrowFrom(silo0, borrowerUsdt);
        emit log_named_decimal_uint("borrowerUsdt LTV", siloLens.getUserLTV(silo1, borrowerUsdt), 16);

        vm.warp(block.timestamp + 300 days);

        emit log_named_decimal_uint("borrowerUsdc LTV", siloLens.getUserLTV(silo0, borrowerUsdc), 16);
        emit log_named_decimal_uint("borrowerUsdt LTV", siloLens.getUserLTV(silo1, borrowerUsdt), 16);

        assertFalse(silo0.isSolvent(borrowerUsdt), "Borrower USDT is still solvent");
        assertFalse(silo0.isSolvent(borrowerUsdc), "Borrower USDC is still solvent");
    }

    function _dealTokens() internal {
        deal(address(token0), depositor, 10e6);
        deal(address(token0), borrowerUsdc, 10e6);
        deal(address(token0), borrowerUsdt, 10e6);

        deal(address(token1), depositor, 10e6);
        deal(address(token1), borrowerUsdc, 10e6);
        deal(address(token1), borrowerUsdt, 10e6);

        emit log_named_decimal_uint("depositor balance", token0.balanceOf(depositor), 6);
        emit log_named_decimal_uint("borrowerUsdc balance", token0.balanceOf(borrowerUsdc), 6);
        emit log_named_decimal_uint("borrowerUsdt balance", token0.balanceOf(borrowerUsdt), 6);

        emit log_named_decimal_uint("depositor balance", token1.balanceOf(depositor), 6);
        emit log_named_decimal_uint("borrowerUsdc balance", token1.balanceOf(borrowerUsdc), 6);
        emit log_named_decimal_uint("borrowerUsdt balance", token1.balanceOf(borrowerUsdt), 6);
    }

    function _depositTo(ISilo _silo, address _depositor) internal {
        vm.startPrank(_depositor);
        IERC20(_silo.asset()).approve(address(_silo), 10e6);
        _silo.deposit(10e6, _depositor);
        vm.stopPrank();
    }
    
    function _depositUsdt(address _depositor) internal {
        vm.startPrank(_depositor);
        usdt.approve(address(silo0), 10e6);
        silo0.deposit(10e6, _depositor);
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
}
