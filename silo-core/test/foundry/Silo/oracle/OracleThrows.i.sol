// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {DummyOracle} from "../../_common/DummyOracle.sol";

/*
    forge test -vv --ffi --mc OracleThrowsTest
*/
contract OracleThrowsTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;
    address immutable DEPOSITOR;
    address immutable BORROWER;

    DummyOracle immutable SOLVENCY_ORACLE0;
    DummyOracle immutable MAX_LTV_ORACLE0;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        BORROWER = makeAddr("Borrower");

        token0 = new MintableToken(18);
        token1 = new MintableToken(18);

        SOLVENCY_ORACLE0 = new DummyOracle(1e18, address(token1));
        MAX_LTV_ORACLE0 = new DummyOracle(1e18, address(token1));

        SOLVENCY_ORACLE0.setExpectBeforeQuote(true);
        MAX_LTV_ORACLE0.setExpectBeforeQuote(true);

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.solvencyOracle0 = address(SOLVENCY_ORACLE0);
        overrides.maxLtvOracle0 = address(MAX_LTV_ORACLE0);
        overrides.configName = SiloConfigsNames.SILO_LOCAL_BEFORE_CALL;

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);
    }

    /*
    forge test -vv --ffi --mt test_throwing_oracle
    */
    function test_throwing_oracle_1token() public {
        // we can not test oracle for 1 token, because we not using it for 1 token
        // _throwing_oracle();
    }

    function _throwing_oracle() private {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;

        _deposit(depositAmount, BORROWER);
        _depositForBorrow(depositAmount, DEPOSITOR);

        _borrow(borrowAmount, BORROWER);

        assertEq(token0.balanceOf(BORROWER), 0);
        assertEq(token0.balanceOf(DEPOSITOR), 0);
        assertEq(token0.balanceOf(address(silo0)), 100e18, "BORROWER collateral");

        assertEq(token1.balanceOf(BORROWER), 50e18, "BORROWER debt");
        assertEq(token1.balanceOf(DEPOSITOR), 0);
        assertEq(token1.balanceOf(address(silo1)), 50e18, "DEPOSITOR's deposit");

        vm.warp(block.timestamp + 100 days);
        silo1.accrueInterest();

        SOLVENCY_ORACLE0.breakOracle();
        MAX_LTV_ORACLE0.breakOracle();

        assertTrue(_withdrawAll(), "expect all tx to be executed till the end");

        assertEq(token0.balanceOf(BORROWER), 100e18, "BORROWER got all collateral");
        assertEq(token0.balanceOf(DEPOSITOR), 0, "DEPOSITOR didnt had token1");
        assertEq(token0.balanceOf(address(silo0)), 0);

        assertEq(token1.balanceOf(BORROWER), 0, "BORROWER repay all debt");
        assertEq(token1.balanceOf(DEPOSITOR), 100e18 + 726118608081294262, "DEPOSITOR got deposit + interest");
        assertEq(token1.balanceOf(address(silo1)), 1, "everyone got collateral and fees, rounding policy left");

        assertEq(silo0.getLiquidity(), 0, "silo0.getLiquidity");
        assertEq(silo1.getLiquidity(), 1, "silo1.getLiquidity");
    }

    function _withdrawAll() internal returns (bool success) {
        vm.prank(BORROWER);
        vm.expectRevert("beforeQuote: oracle is broken");

        ISilo collateralSilo = silo0;
        MintableToken collateralToken = token0;

        collateralSilo.redeem(1, BORROWER, BORROWER);
        assertEq(collateralToken.balanceOf(BORROWER), 0, "BORROWER can not withdraw even 1 wei when oracle broken");

        uint256 silo1Balance = token1.balanceOf(address(silo1));
        uint256 silo1Liquidity = silo1.getLiquidity();
        emit log_named_decimal_uint("silo1Balance", silo1Balance, 18);
        emit log_named_decimal_uint("silo1Liquidity", silo1Liquidity, 18);
        assertGt(silo1Balance, 0, "expect tokens in silo");
        assertGt(silo1Balance, silo1Liquidity, "we need case with interest");

        vm.prank(DEPOSITOR);
        vm.expectRevert();
        silo1.withdraw(silo1Liquidity + 1, DEPOSITOR, DEPOSITOR);
        assertEq(
            token1.balanceOf(DEPOSITOR), 0, "silo has only X tokens available, withdraw for DEPOSITOR will fail"
        );

        vm.prank(DEPOSITOR);
        silo1.withdraw(silo1Liquidity, DEPOSITOR, DEPOSITOR);
        assertEq(
            token1.balanceOf(DEPOSITOR), silo1Liquidity, "DEPOSITOR can withdraw up to liquidity without oracle"
        );
        assertEq(
            token1.balanceOf(address(silo1)), silo1Balance - silo1Liquidity, "no available tokens left in silo"
        );

        _repay(10, BORROWER);
        assertEq(token1.balanceOf(address(silo1)), silo1Balance - silo1Liquidity + 10, "repay without oracle");

        (, address collateralShareToken1, address debtShareToken) = silo1.config().getShareTokens(address(silo1));
        uint256 borrowerDebtShares = IShareToken(debtShareToken).balanceOf(BORROWER);

        _repayShares(silo1.previewRepayShares(borrowerDebtShares), borrowerDebtShares, BORROWER);
        assertEq(
            IShareToken(debtShareToken).balanceOf(BORROWER), 0, "repay all without oracle - expect no share debt"
        );

        (, address collateralShareToken,) = collateralSilo.config().getShareTokens(address(collateralSilo));

        vm.startPrank(BORROWER);
        collateralSilo.redeem(IShareToken(collateralShareToken).balanceOf(BORROWER), BORROWER, BORROWER);

        vm.startPrank(DEPOSITOR);
        silo1.redeem(IShareToken(collateralShareToken1).balanceOf(DEPOSITOR), DEPOSITOR, DEPOSITOR);

        silo1.withdrawFees();

        vm.stopPrank();
        success = true;
    }
}
