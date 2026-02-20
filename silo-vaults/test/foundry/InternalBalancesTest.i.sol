// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {ErrorsLib} from "silo-vaults/contracts/libraries/ErrorsLib.sol";
import {VaultsLittleHelper} from "./fromCore/_common/VaultsLittleHelper.sol";

/*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc InternalBalancesTest -vv
*/
contract InternalBalancesTest is VaultsLittleHelper {
    event SyncBalanceTracker(IERC4626 indexed market, uint256 oldBalance, uint256 newBalance);

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_balanceTracker_Sync_Permissions -vvv
    */
    function test_balanceTracker_Sync_Permissions() public {
        vm.expectRevert(ErrorsLib.NotGuardianRole.selector);
        vault.syncBalanceTracker(IERC4626(address(0)), 0, false);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_balanceTracker_Sync -vvv
    */
    function test_balanceTracker_Sync() public {
        uint256 length = vault.supplyQueueLength();

        assertGt(length, 1, "supplyQueueLength less than 2");

        IERC4626 market0 = vault.supplyQueue(0);

        address depositor = makeAddr("Depositor");

        uint256 depositAmount = 1e18;

        vm.prank(depositor);
        vault.deposit(depositAmount, depositor);

        uint256 balanceAfter = vault.balanceTracker(market0);

        assertEq(balanceAfter, depositAmount, "expect balanceAfter to be depositAmount");

        // for any reason market0 reporting that we have less assets
        // and this is acceptable

        uint256 sharesBalance = market0.balanceOf(address(vault));
        uint256 currentPreviewRedeem = market0.previewRedeem(sharesBalance);

        assertEq(currentPreviewRedeem, depositAmount, "expect currentPreviewRedeem to be depositAmount");

        uint256 newBalance = currentPreviewRedeem / 2;

        bytes memory data = abi.encodeWithSelector(IERC4626.previewRedeem.selector, sharesBalance);

        vm.mockCall(address(market0), data, abi.encode(newBalance));
        vm.expectCall(address(market0), data);

        // we want to sync balances

        vm.expectEmit(true, true, true, true);
        emit SyncBalanceTracker(market0, balanceAfter, newBalance);

        address owner = Ownable(address(vault)).owner();
        vm.prank(owner);
        vault.syncBalanceTracker(market0, 0, false);

        balanceAfter = vault.balanceTracker(market0);

        assertEq(balanceAfter, newBalance, "expect balanceAfter to be newBalance");

        // override balance

        vm.expectEmit(true, true, true, true);
        emit SyncBalanceTracker(market0, newBalance, newBalance + 1);

        vm.prank(owner);
        vault.syncBalanceTracker(market0, newBalance + 1, true);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_balanceTracker_Sync_InvalidOverride -vvv
    */
    function test_balanceTracker_Sync_InvalidOverride() public {
        address owner = Ownable(address(vault)).owner();

        vm.prank(owner);
        vm.expectRevert(ErrorsLib.InvalidOverride.selector);
        vault.syncBalanceTracker(IERC4626(address(0)), 1, false);
    }
}
