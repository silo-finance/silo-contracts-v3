// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";

import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

import {INotificationReceiver} from "../../../contracts/interfaces/INotificationReceiver.sol";

import {VaultRewardsIntegrationSetup} from "./VaultRewardsIntegrationSetup.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc VaultRewardsIntegrationTest -vvv
*/
contract VaultRewardsIntegrationTest is VaultRewardsIntegrationSetup {
    using SafeCast for uint256;
    using SafeCast for uint128;

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_vaults_rewards_noRevert -vv
    */
    function test_vaults_rewards_noRevert() public {
        uint256 amount = 1e18;
        uint256 shares = amount * SiloMathLib._DECIMALS_OFFSET_POW;
        uint256 sharesCapped = amount > _cap() ? _cap() * SiloMathLib._DECIMALS_OFFSET_POW : shares;

        vm.expectCall(
            address(partialLiquidation),
            abi.encodeWithSelector(
                IHookReceiver.afterAction.selector,
                address(silo1),
                Hook.COLLATERAL_TOKEN | Hook.SHARE_TOKEN_TRANSFER,
                abi.encodePacked(
                    address(0),
                    address(vault),
                    uint256(sharesCapped),
                    uint256(0),
                    uint256(sharesCapped),
                    uint256(sharesCapped)
                )
            )
        );

        vault.deposit(amount, address(this));
        assertEq(silo1.totalSupply(), sharesCapped, "we expect deposit to go to silo");

        // does not revert without incentives setup:

        vault.claimRewards();
        siloIncentivesController.claimRewards(address(this));

        assertEq(reward1.balanceOf(address(vault)), 0, "vault has NO rewards");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_vaults_rewards_onDeposit -vv
    */
    function test_vaults_rewards_onDeposit() public {
        _setupIncentives();

        uint256 rewardsPerSec = 3210;

        // standard program for silo users
        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "x",
            rewardToken: address(reward1),
            emissionPerSecond: rewardsPerSec.toUint104(),
            distributionEnd: uint40(block.timestamp + 10)
        }));

        uint256 depositAmount = 2e8;
        uint256 shares = depositAmount * SiloMathLib._DECIMALS_OFFSET_POW;
        uint256 sharesCapped = depositAmount > _cap() ? _cap() * SiloMathLib._DECIMALS_OFFSET_POW : shares;

        vm.expectCall(
            address(siloIncentivesController),
            abi.encodeWithSelector(
                INotificationReceiver.afterTokenTransfer.selector,
                address(0),
                0,
                address(vault),
                sharesCapped,
                sharesCapped,
                sharesCapped
            )
        );

        vm.expectCall(
            address(vaultIncentivesController),
            abi.encodeWithSelector(
                INotificationReceiver.afterTokenTransfer.selector,
                address(0),
                0,
                address(this),
                depositAmount * OFFSET_POW,
                depositAmount * OFFSET_POW,
                depositAmount * OFFSET_POW
            )
        );

        vault.deposit(depositAmount, address(this));
        assertEq(silo1.totalSupply(), sharesCapped, "we expect deposit to go to silo1");

        vm.warp(block.timestamp + 1);
        string memory programName = Strings.toHexString(address(reward1));

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "x"),
            rewardsPerSec,
            "expected rewards for silo after 1s"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "expected ZERO rewards, because they are generated BEFORE deposit"
        );

        // do another deposit, it will distribute
        vm.prank(address(1));
        vault.deposit(1e20, address(1));

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            rewardsPerSec,
            "expected ALL rewards to go to first depositor"
        );

        vaultIncentivesController.claimRewards(address(this));
        assertEq(reward1.balanceOf(address(this)), rewardsPerSec, "claimed rewards");

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "x"),
            0,
            "rewards for silo claimed"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "rewards for vault claimed"
        );
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_vaults_rewards_calculations -vv
    */
    function test_vaults_rewards_calculations() public {
        _setupIncentives();

        uint256 rewardsPerSec = 3210;

        // standard program for silo users
        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "x",
            rewardToken: address(reward1),
            emissionPerSecond: rewardsPerSec.toUint104(),
            distributionEnd: uint40(block.timestamp + 10)
        }));

        uint256 depositAmount = 2e8;
        string memory programName = Strings.toHexString(address(reward1));

        vault.deposit(depositAmount, address(this));

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "expected ZERO rewards, because they are generated BEFORE deposit"
        );

        vault.claimRewards();

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "claimRewards will not generate any rewards, because incentives state was calculated before user deposit"
        );

        vault.withdraw(depositAmount / 2, address(this), address(this));

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "rewards should not be generated by withdraw"
        );

        vm.warp(block.timestamp + 1);
        vault.claimRewards();

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            rewardsPerSec,
            "1s when additional time pass getRewardsBalance returns rewards to claim"
        );

        vm.warp(block.timestamp + 1);
        vault.claimRewards();

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            rewardsPerSec * 2,
            "2s when additional time pass getRewardsBalance returns rewards to claim"
        );

        vaultIncentivesController.claimRewards(address(this));
        assertEq(reward1.balanceOf(address(this)), rewardsPerSec * 2, "claimed rewards");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_1secondDistribution_pass -vv
    */
    function test_1secondDistribution_pass() public {
        uint128 depositAmount = 123e18;
        uint128 rewardsPerSec = 123456789123453000; // zeros at the end to avoid precision errors

        _setupIncentives();

        vault.deposit(depositAmount, address(this));

        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "program1",
            rewardToken: address(reward1),
            emissionPerSecond: rewardsPerSec.toUint104(),
            distributionEnd: uint40(block.timestamp + 1)
        }));

        vm.warp(block.timestamp + 100);

        uint256 siloRewardPreview = siloIncentivesController.getRewardsBalance(address(vault), "program1");

        assertEq(siloRewardPreview, rewardsPerSec, "expected rewards for silo for 1s");

        vault.claimRewards();
        string memory programName1 = Strings.toHexString(address(reward1));

        uint256 vaultRewardPreview = vaultIncentivesController.getRewardsBalance(address(this), programName1);

        assertEq(siloRewardPreview, vaultRewardPreview, "with 1 user rewards for silo == rewards for vault");

        assertEq(vaultRewardPreview, rewardsPerSec, "expected rewards for vault for 1s");

        vaultIncentivesController.claimRewards(address(this));

        assertEq(reward1.balanceOf(address(this)), vaultRewardPreview, "user got rewards");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_1secondDistribution_fuzz -vv
    */
    function test_1secondDistribution_fuzz(uint128 _depositAmount, uint128 _rewardsPerSec) public {
        vm.assume(_rewardsPerSec > 1e3 && _rewardsPerSec < 1e30);
        vm.assume(_depositAmount > 0);

        _setupIncentives();

        vault.deposit(_depositAmount, address(this));

        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "program1",
            rewardToken: address(reward1),
            emissionPerSecond: _rewardsPerSec.toUint104(),
            distributionEnd: uint40(block.timestamp + 1)
        }));

        vm.warp(block.timestamp + 100);

        uint256 siloRewardPreview = siloIncentivesController.getRewardsBalance(address(vault), "program1");

        assertLe(siloRewardPreview, _rewardsPerSec,"[silo] we can not get more that was set for 1s");

        vault.claimRewards();
        string memory programName1 = Strings.toHexString(address(reward1));

        uint256 vaultRewardPreview = vaultIncentivesController.getRewardsBalance(address(this), programName1);

        assertLe(vaultRewardPreview, siloRewardPreview, "vault rewards can not be higher than claimed from silo");

        assertLe(vaultRewardPreview, _rewardsPerSec, "[vault] we can not get more that was set for 1s");

        vaultIncentivesController.claimRewards(address(this));

        assertEq(reward1.balanceOf(address(this)), vaultRewardPreview, "user got rewards");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_pastDistributionEnd_afterDeposit -vv
    */
    function _assertNoRewards(address _user, string memory _program) internal {

        uint256 siloRewardPreview = siloIncentivesController.getRewardsBalance(address(vault), _program);

        assertLe(siloRewardPreview, 0,"[silo] no rewards on silo incentive");

        vault.claimRewards();
        string memory programName1 = Strings.toHexString(address(reward1));

        uint256 vaultRewardPreview = vaultIncentivesController.getRewardsBalance(_user, programName1);

        assertEq(vaultRewardPreview, 0, "vault rewards 0");

        vaultIncentivesController.claimRewards(_user);

        assertEq(reward1.balanceOf(_user), 0, "user got ZERO rewards");
    }
}
