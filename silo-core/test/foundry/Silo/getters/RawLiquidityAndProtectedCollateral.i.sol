// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";

contract RawLiquidityAndProtectedCollateralTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    ISiloConfig internal _siloConfig;

    function setUp() public {
        SiloFixture siloFixture = new SiloFixture();
        SiloConfigOverride memory configOverride;

        token0 = new MintableToken(18);
        token1 = new MintableToken(18);

        configOverride.token0 = address(token0);
        configOverride.token1 = address(token1);

        address hook;
        (_siloConfig, silo0, silo1,,, hook) = siloFixture.deploy_local(configOverride);
        partialLiquidation = IPartialLiquidation(hook);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testLiquidityAndProtectedAssets
    */
    function testLiquidityAndProtectedAssets() public {
        address user0 = makeAddr("user0");
        address user1 = makeAddr("user1");
        address depositorProtected = makeAddr("depositProtected");

        uint256 depositAmount = 1000;

        _deposit(silo0, token0, user0, depositAmount, ISilo.CollateralType.Collateral);
        _printSiloStats("\nStep1 deposit collateral 1000 (Silo0)", silo0, token0);

        // for borrow
        _deposit(silo1, token1, user1, depositAmount, ISilo.CollateralType.Collateral);

        vm.warp(block.timestamp + 30 days);

        uint256 borrowAmount = 750; // maxLtv = 75%
        vm.prank(user1);
        silo0.borrow(borrowAmount, user1, user1);
        _printSiloStats("\nStep2 borrow 750 (Silo0)", silo0, token0);

        vm.prank(user0);
        silo1.borrow(borrowAmount, user0, user0);

        vm.warp(block.timestamp + 30 days);

        _deposit(silo0, token0, depositorProtected, depositAmount, ISilo.CollateralType.Protected);
        _printSiloStats("\nStep3 deposit protected 1000 (Silo0)", silo0, token0);

        vm.warp(block.timestamp + 365 days);
        silo0.accrueInterest();
        _printSiloStats("\nStep4 accrueInterest in 365 days (Silo0)", silo0, token0);

        silo0.withdrawFees();
        _printSiloStats("\nStep5 withdraw fees (Silo0)", silo0, token0);

        // liquidation
        (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(user0);

        assertGt(collateralToLiquidate, 0, "expect collateralToLiquidate");
        assertTrue(sTokenRequired, "sTokenRequired required because NotEnoughLiquidity");

        token1.mint(address(this), debtToRepay); // address(this) is liquidator
        token1.approve(address(partialLiquidation), debtToRepay);

        vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        partialLiquidation.liquidationCall(
            address(token0), address(token1), user0, debtToRepay, false /* receive share tokens */
        );

        // If there is not liquidity in the silo, the liquidator can receive share tokens

        (, address collateralShareToken,) = _siloConfig.getShareTokens(address(silo0));

        assertEq(IERC20(collateralShareToken).balanceOf(address(this)), 0, "expect 0 balance");

        partialLiquidation.liquidationCall(
            address(token0), address(token1), user0, debtToRepay, true /* receive share tokens */
        );

        assertGt(IERC20(collateralShareToken).balanceOf(address(this)), 0, "expect balance");
    }

    function _printSiloStats(string memory _step, ISilo _silo, MintableToken _token) internal {
        emit log(_step);

        (uint256 collateralAssets, uint256 protectedAssets) = _silo.getCollateralAndProtectedTotalsStorage();
        uint256 debtAssets = _silo.getDebtAssets();
        (uint192 daoAndDeployerRevenue,,,,) = _silo.getSiloStorage();
        uint256 liquidity = _silo.getRawLiquidity();

        emit log_named_uint("collateralAssets", collateralAssets);
        emit log_named_uint("protectedAssets", protectedAssets);
        emit log_named_uint("debtAssets", debtAssets);
        emit log_named_uint("daoAndDeployerRevenue", daoAndDeployerRevenue);
        emit log_named_uint("liquidity", liquidity);
        emit log_named_uint("silo balance", _token.balanceOf(address(_silo)));
    }

    function _deposit(
        ISilo _silo,
        MintableToken _token,
        address _depositorAddr,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        _token.mint(_depositorAddr, _amount);

        vm.prank(_depositorAddr);
        _token.approve(address(_silo), _amount);

        vm.prank(_depositorAddr);
        _silo.deposit(_amount, _depositorAddr, _collateralType);
    }
}
