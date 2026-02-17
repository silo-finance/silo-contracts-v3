// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc CollateralTokenInflationAttack
*/
contract CollateralTokenInflationAttack is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    ISiloConfig public siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_vault_denial_of_service_attack_deposit_lock

    @dev An issue resolved by increasing the decimals offset for the collateral share token.
         See silo-core/contracts/lib/SiloMathLib.sol _DECIMALS_OFFSET_POW
    */
    function test_vault_denial_of_service_attack_deposit_lock() public {
        address victim = makeAddr("Victim");

        _messWithRatio();

        uint256 siloCollateralAssets = silo0.getCollateralAssets();

        assertEq(siloCollateralAssets, 1_073_741_825, "sanity check for silo collateral assets");

        // prepare to deposit
        _mintTokens(token0, siloCollateralAssets, victim);

        vm.prank(victim);
        token0.approve(address(silo0), siloCollateralAssets);

        // The user is able to deposit after SiloMathLib._DECIMALS_OFFSET_POW set to 10 ** 3
        vm.prank(victim); // the victim is not victim anymore
        silo0.deposit(1e8, victim, ISilo.CollateralType.Collateral);

        // The following is true only if SiloMathLib._DECIMALS_OFFSET_POW = 10 ** 0
        // because of that the the following code is commented.

        // siloCollateralAssets : 1073741825
        // 1 share =            : 536870913
        // "limit" is 50% of siloCollateralAssets
        // vm.prank(victim);
        // vm.expectRevert(ISilo.ZeroShares.selector);
        // silo0.deposit(1e8, victim, ISilo.CollateralType.Collateral);

        // vm.prank(victim);
        // uint256 shares = silo0.deposit(siloCollateralAssets, victim, ISilo.CollateralType.Collateral);

        // assertEq(shares, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_vault_denial_of_service_attack_funds_recovery

    @dev An issue resolved by increasing the decimals offset for the collateral share token.
         See silo-core/contracts/lib/SiloMathLib.sol _DECIMALS_OFFSET_POW
    */
    function test_vault_denial_of_service_attack_funds_recovery() public {
        address attacker = makeAddr("Attacker");

        uint256 attackerDeposits = _messWithRatio();

        for (uint256 i = 0; i < 15; i++) {
            string memory user = vm.toString(i + 1);
            address depositor = makeAddr(user);

            uint256 toDeposit = silo0.getCollateralAssets();
            _makeDeposit(silo0, token0, toDeposit, depositor, ISilo.CollateralType.Collateral);
        }

        // attacker redeeming the deposit
        uint256 redeemShares = silo0.maxRedeem(attacker);

        vm.prank(attacker);
        uint256 receivedAmount = silo0.redeem(redeemShares, attacker, attacker);

        assertEq(attackerDeposits, 1073741823, "sum of attacker deposits");
        assertEq(receivedAmount, 1073741824, "attacker received amount"); // 1 wei more?

        // The following is true only if SiloMathLib._DECIMALS_OFFSET_POW = 10 ** 0

        // assertEq(attackerDeposits, 1073741823);
        // assertEq(receivedAmount,   1073709057);
        // assertEq(attackerDeposits - receivedAmount, 32766);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_vault_denial_of_service_attack_withdraw_issue

    @dev An issue resolved by increasing the decimals offset for the collateral share token.
         See silo-core/contracts/lib/SiloMathLib.sol _DECIMALS_OFFSET_POW
    */
    function test_vault_denial_of_service_attack_withdraw_issue() public {
        _messWithRatio();

        uint256 numberOfDepositors = 10;

        address[] memory depositors = new address[](numberOfDepositors);
        uint256[] memory depositsAmounts = new uint256[](numberOfDepositors);

        for (uint256 i = 0; i < numberOfDepositors; i++) {
            string memory user = vm.toString(i + 1);
            address _depositor = makeAddr(user);
            depositors[i] = _depositor;

            uint256 toDeposit = silo0.getCollateralAssets();
            _makeDeposit(silo0, token0, toDeposit, _depositor, ISilo.CollateralType.Collateral);

            depositsAmounts[i] = toDeposit;
        }

        uint256 anyDepositor = 9;
        address depositor = depositors[anyDepositor];

        // The user is able to withdraw after SiloMathLib._DECIMALS_OFFSET_POW set to 10 ** 3
        // -1 for underestimation
        vm.prank(depositor);
        silo0.withdraw(depositsAmounts[anyDepositor] - 1, depositor, depositor);

        // The following is true only if SiloMathLib._DECIMALS_OFFSET_POW = 10 ** 0
        // because of that the the following code is commented.

        // (, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));
        // uint256 sharesBalance = IShareToken(collateralShareToken).balanceOf(depositor);

        // withdrawing the deposit
        // vm.prank(depositor);

        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         IERC20Errors.ERC20InsufficientBalance.selector,
        //         depositor,
        //         sharesBalance,
        //         sharesBalance + 1 wei
        //     )
        // );

        // silo0.withdraw(depositsAmounts[anyDepositor], depositor, depositor);

        // uint256 maxWithdraw = silo0.maxWithdraw(depositor);

        // emit log_named_uint("maxWithdraw", maxWithdraw);

        // // redeeming the deposit
        // uint256 redeemShares = silo0.maxRedeem(depositor);

        // assertEq(redeemShares, sharesBalance);

        // vm.prank(depositor);
        // uint256 receivedAmount = silo0.redeem(redeemShares, depositor, depositor);

        // // depositor received less than he deposited and a difference is > 1e6 (arbitrary number)
        // assertTrue(depositsAmounts[anyDepositor] - receivedAmount > 1e6);

        // // depositor received all his shares
        // sharesBalance = IShareToken(collateralShareToken).balanceOf(depositor);
        // assertEq(sharesBalance, 0);

        // uint256 balanceOfDepositor = token0.balanceOf(depositor);
        // assertEq(receivedAmount, balanceOfDepositor);

        // emit log_named_uint("receivedAmount: ", receivedAmount);
        // emit log_named_uint("depositAmount: ", depositsAmounts[anyDepositor]);
    }

    function _messWithRatio() internal returns (uint256 depositedForAttack) {
        address attacker = makeAddr("Attacker");
        address borrower = makeAddr("Attacker Borrower");

        uint256 gasStart = gasleft();

        _makeDeposit(silo0, token0, 1, attacker, ISilo.CollateralType.Collateral);

        _borrowAndRepay(borrower, 200);

        uint256 borrowerShares = silo0.maxRedeem(borrower);

        vm.prank(borrower);
        silo0.redeem(borrowerShares, borrower, borrower);

        silo0.accrueInterest();

        for (uint256 i = 0; i < 30; i++) {
            uint256 toDeposit = silo0.getCollateralAssets();
            _makeDeposit(silo0, token0, toDeposit, attacker, ISilo.CollateralType.Collateral);
            depositedForAttack += toDeposit;

            vm.prank(attacker);
            silo0.withdraw(1, attacker, attacker);
            depositedForAttack -= 1;
        }

        emit log_named_uint("[_doAttack] gas used: ", gasStart - gasleft());
    }

    function _borrowAndRepay(address _borrower, uint256 _toBorrow) internal {
        uint256 depositAmount = _toBorrow * 12 / 8;

        _makeDeposit(silo0, token0, depositAmount, _borrower, ISilo.CollateralType.Collateral);
        _makeDeposit(silo1, token1, depositAmount, _borrower, ISilo.CollateralType.Collateral);

        vm.prank(_borrower);
        uint256 shares = silo0.borrow(_toBorrow, _borrower, _borrower);

        vm.warp(block.timestamp + 70 days);

        uint256 toRepay = silo0.maxRepay(_borrower);

        vm.prank(_borrower);
        token0.approve(address(silo0), toRepay);

        _mintTokens(token0, toRepay, _borrower);

        // why this assertion was here originally? idk, dees not make sense to me if the goal is to repay
        // assertTrue(silo0.isSolvent(_borrower), "[_borrowAndRepay] expect solvent borrower");

        vm.prank(_borrower);
        shares = silo0.repay(toRepay, _borrower);
    }
}
