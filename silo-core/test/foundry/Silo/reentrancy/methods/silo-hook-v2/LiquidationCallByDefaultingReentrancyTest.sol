// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract LiquidationCallByDefaultingReentrancyTest is MethodReentrancyTest {
    address public depositor = makeAddr("DepositorLiquidation");
    address public borrower = makeAddr("BorrowerLiquidation");

    address public depositorOnReentrancy = makeAddr("DepositorLiquidationReentrancy");
    address public borrowerOnReentrancy = makeAddr("BorrowerLiquidationReentrancy");

    function callMethod() external {
        // disable reentrancy check in the test so we will not check it on deposit/borrow
        TestStateLib.disableReentrancy();
        _createInsolventBorrower(depositor, borrower);

        // Enable reentrancy to check in the test so we can check it during the liquidation.
        TestStateLib.enableReentrancy();
        TestStateLib.setReenterViaLiquidationCall(true);

        _liquidationCallByDefaulting(borrower, bytes4(0));

        TestStateLib.setReenterViaLiquidationCall(false);
    }

    function verifyReentrancy() external {
        ISiloConfig siloConfig = TestStateLib.siloConfig();
        address hookReceiver = TestStateLib.hookReceiver();

        // Disable reentrancy to create insolvent borrower.
        vm.prank(hookReceiver);
        siloConfig.turnOffReentrancyProtection();

        _createInsolventBorrower(depositorOnReentrancy, borrowerOnReentrancy);

        // Enable reentrancy to test liquidation with insolvent borrower.
        // We return to the previous state.
        vm.prank(hookReceiver);
        siloConfig.turnOnReentrancyProtection();

        IPartialLiquidation partialLiquidation = IPartialLiquidation(hookReceiver);

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrowerOnReentrancy);

        if (debtToRepay == 0) {
            console2.log(_logPrefix("user not ready for liquidation"));
            revert(_logPrefix("user not ready for liquidation"));
        }

        bytes4 expectRevert;

        if (TestStateLib.reenterViaLiquidationCall()) {
            expectRevert = TransientReentrancy.ReentrancyGuardReentrantCall.selector;
        } else {
            expectRevert = ICrossReentrancyGuard.CrossReentrantCall.selector;
        }

        _liquidationCallByDefaulting(borrowerOnReentrancy, expectRevert);
    }

    function _liquidationCallByDefaulting(address _borrower, bytes4 _expectRevert) internal virtual {
        IPartialLiquidationByDefaulting partialLiquidation =
            IPartialLiquidationByDefaulting(TestStateLib.hookReceiver());

        if (_expectRevert != bytes4(0)) {
            vm.expectRevert(_expectRevert);
        }
            
        vm.prank(_borrower);
        partialLiquidation.liquidationCallByDefaulting(_borrower);
    }

    function methodDescription() external pure virtual returns (string memory description) {
        description = "liquidationCallByDefaulting(address)";
    }

    function _createInsolventBorrower(address _depositor, address _borrower) internal {
        MaliciousToken token0 = MaliciousToken(TestStateLib.token0());
        MaliciousToken token1 = MaliciousToken(TestStateLib.token1());
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();
        // in case we in reentrancy, we can have case with 0 liquidity, so we need to make sure
        // we deposit enough to be able to borrow
        uint256 liquidityForBorrow = 10e18 + silo0.totalAssets();
        uint256 collateralAmount = 10e18;

        token0.mint(_depositor, liquidityForBorrow);

        vm.prank(_depositor);
        token0.approve(address(silo0), liquidityForBorrow);

        vm.prank(_depositor);
        silo0.deposit(liquidityForBorrow, _depositor);

        token1.mint(_borrower, collateralAmount);

        vm.prank(_borrower);
        token1.approve(address(silo1), collateralAmount);

        vm.prank(_borrower);
        silo1.deposit(collateralAmount, _borrower);

        uint256 maxBorrow = silo0.maxBorrow(_borrower) / 2;

        if (maxBorrow == 0) {
            console2.log(_logPrefix("we can't borrow"));
            revert(_logPrefix("we can't borrow"));
        }

        vm.prank(_borrower);
        silo0.borrow(maxBorrow, _borrower, _borrower);

        _makeUserInsolvent(_borrower, _depositor);
    }

    function _makeUserInsolvent(address _borrower, address _depositor) internal {
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        uint256 maxWithdraw = silo1.maxWithdraw(_borrower);

        if (maxWithdraw != 0) {
            vm.prank(_borrower);
            silo1.withdraw(maxWithdraw, _borrower, _borrower);
        }

        maxWithdraw = silo0.maxWithdraw(_depositor);

        if (maxWithdraw != 0) {
            vm.prank(_depositor);
            silo0.withdraw(maxWithdraw, _depositor, _depositor);
        }

        uint256 y;

        while (silo0.isSolvent(_borrower)) {
            y++;
            vm.warp(block.timestamp + 365 days);
        }

        console2.log(_tabs(4), _logPrefix("years warp"), y);
    }

    function _logPrefix(string memory _msg) internal pure virtual returns (string memory) {
        return string.concat("[LiquidationCallByDefaultingReentrancyTest] ", _msg);
    }
}
