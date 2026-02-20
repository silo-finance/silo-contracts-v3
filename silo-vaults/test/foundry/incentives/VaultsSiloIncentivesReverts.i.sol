// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {INotificationReceiver} from "../../../contracts/interfaces/INotificationReceiver.sol";
import {IntegrationTest} from "../helpers/IntegrationTest.sol";
import {CAP} from "../helpers/BaseTest.sol";

import {ErrorsLib} from "silo-vaults/contracts/libraries/ErrorsLib.sol";

import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";
import {IIncentivesClaimingLogic} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogic.sol";
import {IncentivesControllerWithRevert} from "../mocks/IncentivesControllerWithRevert.sol";
import {IncentivesClaimingLogicWithRevert} from "../mocks/IncentivesClaimingLogicWithRevert.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc VaultsSiloIncentivesTest -vvv
*/
contract VaultsSiloIncentivesTest is IntegrationTest {
    MintableToken internal reward1 = new MintableToken(18);

    ISiloIncentivesController vaultIncentivesController;
    IVaultIncentivesModule vaultIncentivesModule;

    function setUp() public override {
        super.setUp();
        _setCap(allMarkets[0], CAP);
        reward1.setOnDemand(true);

        vaultIncentivesModule = vault.INCENTIVES_MODULE();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_revert_claimRewards -vvv
    */
    function test_revert_claimRewards() public {
        IncentivesClaimingLogicWithRevert claimingLogic = new IncentivesClaimingLogicWithRevert();

        vm.prank(OWNER);
        vaultIncentivesModule.submitIncentivesClaimingLogic(
            allMarkets[0],
            IIncentivesClaimingLogic(address(claimingLogic))
        );

        vm.warp(block.timestamp + vault.timelock() + 1);

        vm.prank(OWNER);
        vaultIncentivesModule.acceptIncentivesClaimingLogic(
            allMarkets[0],
            IIncentivesClaimingLogic(address(claimingLogic))
        );

        vm.expectRevert(ErrorsLib.ClaimRewardsFailed.selector);
        vault.claimRewards();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_revert_notificationFailed -vvv
    */
    function test_revert_notificationFailed() public {
        address user = makeAddr("user");
        uint256 depositAmount = 1;
        IncentivesControllerWithRevert incentivesController = new IncentivesControllerWithRevert();

        vm.prank(OWNER);
        vaultIncentivesModule.addNotificationReceiver(INotificationReceiver(address(incentivesController)));

        vm.prank(user);
        vm.expectRevert(IncentivesControllerWithRevert.NotificationFailed.selector);
        vault.deposit(depositAmount, user);
    }
}
