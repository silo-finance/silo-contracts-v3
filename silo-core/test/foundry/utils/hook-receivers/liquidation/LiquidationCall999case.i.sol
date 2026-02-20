// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc LiquidationCall999caseTest
*/
contract LiquidationCall999caseTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;
    using SafeCast for uint256;

    address immutable DEPOSITOR;
    address immutable BORROWER;
    uint256 constant COLLATERAL = 10e18;
    uint256 constant COLLATERAL_FOR_BORROW = 8e18;
    uint256 constant DEBT = 7.5e18;

    ISiloConfig siloConfig;
    uint256 debtStart;

    ISiloConfig.ConfigData silo0Config;
    ISiloConfig.ConfigData silo1Config;

    error SenderNotSolventAfterTransfer();

    constructor() {
        DEPOSITOR = makeAddr("depositor");
        BORROWER = makeAddr("borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        _depositForBorrow(COLLATERAL_FOR_BORROW, DEPOSITOR);
        emit log_named_decimal_uint("COLLATERAL_FOR_BORROW", COLLATERAL_FOR_BORROW, 18);

        _deposit(COLLATERAL, BORROWER);
        _borrow(DEBT, BORROWER);
        emit log_named_decimal_uint("DEBT", DEBT, 18);
        debtStart = block.timestamp;

        assertEq(token0.balanceOf(address(this)), 0, "liquidation should have no collateral");
        assertEq(token0.balanceOf(address(silo0)), COLLATERAL, "silo0 has borrower collateral");
        assertEq(token1.balanceOf(address(silo1)), 0.5e18, "silo1 has only 0.5 debt token (8 - 7.5)");

        silo0Config = siloConfig.getConfig(address(silo0));
        silo1Config = siloConfig.getConfig(address(silo1));

        assertEq(silo0Config.liquidationFee, 0.05e18, "liquidationFee0");
        assertEq(silo1Config.liquidationFee, 0.025e18, "liquidationFee1");

        token0.setOnDemand(true);
        token1.setOnDemand(true);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_NoCollateralToLiquidate
    */
    function test_liquidationCall_NoCollateralToLiquidate() public {
        vm.warp(block.timestamp + 365 days);
        uint256 ltv = SILO_LENS.getLtv(silo0, BORROWER);
        assertGt(ltv, 1e18, "expect bad debt for this test");

        // price is 1:1 so we wil use collateral value as max debt to cover
        (uint256 collateralToLiquidate,,) = partialLiquidation.maxLiquidation(BORROWER);

        partialLiquidation.liquidationCall(
            address(token0), address(token1), BORROWER, collateralToLiquidate, false /* receiveSToken */
        );

        ltv = SILO_LENS.getLtv(silo0, BORROWER);
        assertEq(ltv, type(uint256).max, "expect ininite LTV after liquidation");

        vm.expectRevert(IPartialLiquidation.NoCollateralToLiquidate.selector);
        partialLiquidation.liquidationCall(
            address(token0), address(token1), BORROWER, type(uint256).max, false /* receiveSToken */
        );
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_999protected

    this is test for 999 case bug 
    scenario is: borrower has protected collateral and 999 regular collateral, 
    on liquidation we use both collaterals but protected can not be translated to assets, so tx reverts
    this test fails for v3.12.0
    */
    function test_liquidationCall_999protected() public {
        _liquidationCall_999case(ISilo.CollateralType.Protected);
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_liquidationCall_999collateral
    */
    function test_liquidationCall_999collateral() public {
        vm.startPrank(BORROWER);
        silo0.transitionCollateral(silo0.balanceOf(BORROWER), BORROWER, ISilo.CollateralType.Collateral);
        vm.stopPrank();

        _liquidationCall_999case(ISilo.CollateralType.Collateral);
    }

    function _liquidationCall_999case(ISilo.CollateralType _generateDustForType) internal {
        (IShareToken shareToken, IShareToken otherShareToken) = _generateDustForType == ISilo.CollateralType.Protected
            ? (IShareToken(silo0Config.protectedShareToken), IShareToken(silo0Config.collateralShareToken))
            : (IShareToken(silo0Config.collateralShareToken), IShareToken(silo0Config.protectedShareToken));

        vm.warp(block.timestamp + 50 days);

        _makeSharesNotWithdrawable(_generateDustForType);

        emit log_named_decimal_uint("borrower other shares", otherShareToken.balanceOf(BORROWER), 18);

        emit log_named_decimal_uint("LTV before liquidation [%]", SILO_LENS.getLtv(silo0, BORROWER), 16);

        uint256 sharesBefore = shareToken.balanceOf(address(this));
        assertEq(sharesBefore, 0, "liquidator should have no shares before liquidation");

        uint256 otherSharesBefore = otherShareToken.balanceOf(address(this));
        assertEq(otherSharesBefore, 0, "liquidator should have no other shares before liquidation");

        console2.log("--- LIQUIDATION CALL ---");

        _executeLiquidation();

        uint256 sharesBalanceAfter = shareToken.balanceOf(address(this));
        emit log_named_string("shares token", shareToken.symbol());
        emit log_named_uint("sharesBalanceAfter", sharesBalanceAfter);

        uint256 otherSharesBalanceAfter = otherShareToken.balanceOf(address(this));
        emit log_named_string("other shares token", otherShareToken.symbol());
        emit log_named_uint("otherSharesBalanceAfter", otherSharesBalanceAfter);

        assertGt(sharesBalanceAfter, 0, "liquidator should got dust shares");
        assertEq(
            silo0.previewRedeem(sharesBalanceAfter, _generateDustForType),
            0,
            "liquidator should got non withdrawable shares"
        );

        assertEq(otherSharesBalanceAfter, 0, "liquidator should have no other shares after liquidation");
    }

    function _executeLiquidation() internal {
        partialLiquidation.liquidationCall(
            address(token0), address(token1), BORROWER, type(uint256).max, false /* receiveSToken */
        );
    }

    function _makeSharesNotWithdrawable(ISilo.CollateralType _generateDustForType) internal {
        (IShareToken shareToken, IShareToken otherShareToken) = _generateDustForType == ISilo.CollateralType.Protected
            ? (IShareToken(silo0Config.protectedShareToken), IShareToken(silo0Config.collateralShareToken))
            : (IShareToken(silo0Config.collateralShareToken), IShareToken(silo0Config.protectedShareToken));

        _deposit(1e18, DEPOSITOR, _generateDustForType);

        uint256 borrowerShares = shareToken.balanceOf(BORROWER);
        emit log_named_uint("borrower non witdrawable shares (1)", borrowerShares);

        vm.prank(address(silo0));
        shareToken.burn(DEPOSITOR, DEPOSITOR, 123456789);

        uint256 ratio = silo0.convertToShares(1, ISilo.AssetType(uint8(_generateDustForType)));
        emit log_named_uint("ratio", ratio);
        assertLt(ratio, 1e3, "for this test we expect ratio to be NOT 1:1");

        vm.prank(BORROWER);
        silo0.mint(ratio + 1, BORROWER, _generateDustForType);

        uint256 reduceCollateralValue = otherShareToken.balanceOf(BORROWER) / 2;
        vm.prank(address(partialLiquidation));
        otherShareToken.forwardTransferFromNoChecks(BORROWER, makeAddr("random"), reduceCollateralValue);

        borrowerShares = shareToken.balanceOf(BORROWER);
        emit log_named_uint("borrower non witdrawable shares (2)", borrowerShares);

        assertEq(
            silo0.previewRedeem(borrowerShares, _generateDustForType), 1, "we need shares to generate 1 wei of assets"
        );

        assertEq(
            silo0.previewRedeem(borrowerShares - 1, _generateDustForType),
            0,
            "we need shares to be not withdrawable when rounding down"
        );
    }
}
