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

contract PartialLiquidationUsdtTest is SiloLittleHelper, IntegrationTest {
    address depositor = makeAddr("Depositor");
    address borrowerUsdt = makeAddr("BorrowerUSDT");
    address borrowerUsdc = makeAddr("BorrowerUSDC");

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 24498300);

        AddrLib.init();

        token0 = MintableToken(getAddress("USDT"));
        token1 = MintableToken(getAddress("USDC"));
        vm.label(address(token0), "USDT");
        vm.label(address(token1), "USDC");

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);

        overrides.configName = SiloConfigsNames.SILO_MOCKED;

        SiloFixture siloFixture = new SiloFixture();

        (, silo0, silo1,,,) = siloFixture.deploy_local(overrides);
    }

    /*
    AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_setup
    */
    function test_setup() public {
        _dealTokens();

        // _depositTo(silo0, depositor);
        // _depositTo(silo1, depositor);

        // _borrowFrom(silo0, borrowerUsdc);
        // _borrowFrom(silo1, borrowerUsdt);

        // vm.warp(block.timestamp + 300 days);

        // assertFalse(silo0.isSolvent(borrowerUsdt), "Borrower USDT is still solvent");
        // assertFalse(silo0.isSolvent(borrowerUsdc), "Borrower USDC is still solvent");
    }

    function _dealTokens() internal {
        console2.log("dealing tokens", address(silo0.asset()));
        address usdtWhale = 0xCECD6c10c2B02E735A327554E3110B2BE8Bb26FC;
        _dealToken(usdtWhale, token0);

        // console2.log("dealing tokens", address(silo1.asset()));
        // address usdcWhale = 0xaB851a4FD55E040B3958064028EB9EdDcBCdA33b;
        // _dealToken(usdcWhale, token1);
    }

    function _dealToken(address _whale, IERC20 _token) internal {
        console2.log("dealing token", address(_token));
        emit log_named_decimal_uint("whale balance", _token.balanceOf(_whale), 6);

        vm.prank(_whale);
        _token.transfer(depositor, 10e6);

        // vm.prank(_whale);
        // _token.transfer(borrowerUsdc, 10e6);

        // vm.prank(_whale);
        // _token.transfer(borrowerUsdt, 10e6);
    }

    function _depositTo(ISilo _silo, address _depositor) internal {
        vm.startPrank(_depositor);
        IERC20(_silo.asset()).approve(address(_silo), 1e6);
        _silo.deposit(1e6, _depositor);
        vm.stopPrank();
    }

    function _borrowFrom(ISilo _debtSilo, address _borrower) internal {
        vm.startPrank(_borrower);

        ISilo collateralSilo = address(_debtSilo) == address(silo0) ? silo1 : silo0;

        IERC20(collateralSilo.asset()).approve(address(collateralSilo), 1e6);
        collateralSilo.deposit(1e6, _borrower);
        
        uint256 maxBorrow = _debtSilo.maxBorrow(_borrower);
        _borrow(maxBorrow, _borrower);

        uint256 maxWithdraw = collateralSilo.maxWithdraw(_borrower);
        collateralSilo.withdraw(maxWithdraw, _borrower, _borrower);

        vm.stopPrank();
    }
}
