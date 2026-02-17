// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    SiloIncentivesControllerCL
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCL.sol";

import {
    SiloIncentivesControllerCLFactory
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCLFactory.sol";

import {
    SiloIncentivesControllerCLFactoryDeploy
} from "silo-vaults/deploy/SiloIncentivesControllerCLFactoryDeploy.s.sol";

import {
    ISiloIncentivesController,
    IDistributionManager
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {IIncentivesClaimingLogic} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogic.sol";

// FOUNDRY_PROFILE=vaults_tests forge test -vvv --ffi --mc SiloIncentivesControllerCLTest
contract SiloIncentivesControllerCLTest is Test {
    SiloIncentivesControllerCL public incentivesControllerCL;
    SiloIncentivesControllerCLFactory public factory;

    address internal _vaultIncentivesController = makeAddr("VaultIncentivesController");
    address internal _siloIncentivesController = makeAddr("SiloIncentivesController");

    function setUp() public {
        SiloIncentivesControllerCLFactoryDeploy factoryDeploy = new SiloIncentivesControllerCLFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();
        factory = SiloIncentivesControllerCLFactory(factoryDeploy.run());

        incentivesControllerCL = factory.createIncentivesControllerCL(
            _vaultIncentivesController,
            _siloIncentivesController,
            bytes32(0)
        );

        assertTrue(SiloIncentivesControllerCLFactory(factory).createdInFactory(address(incentivesControllerCL)));
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testCreateIncentivesControllerCLSameOrder -vvv
    */
    function testCreateIncentivesControllerCLSameOrder() public {
        address devWallet = makeAddr("dev wallet");
        address otherWallet = makeAddr("other wallet");

        uint256 snapshot = vm.snapshotState();

        vm.prank(devWallet);
        SiloIncentivesControllerCL logic1 = factory.createIncentivesControllerCL(
            _vaultIncentivesController,
            _siloIncentivesController,
            bytes32(0)
        );

        vm.revertToState(snapshot);

        vm.prank(otherWallet);
        SiloIncentivesControllerCL logic2 = factory.createIncentivesControllerCL(
            _vaultIncentivesController,
            _siloIncentivesController,
            bytes32(0)
        );

        assertNotEq(address(logic1), address(logic2), "logic1 == logic2");
    }

    // FOUNDRY_PROFILE=vaults_tests forge test -vvv --ffi --mt test_incentivesClaimingLogicZeroAddress
    function test_incentivesClaimingLogicZeroAddress() public {
        vm.expectRevert(IIncentivesClaimingLogic.VaultIncentivesControllerZeroAddress.selector);
        factory.createIncentivesControllerCL(address(0), _siloIncentivesController, bytes32(0));

        vm.expectRevert(IIncentivesClaimingLogic.SiloIncentivesControllerZeroAddress.selector);
        factory.createIncentivesControllerCL(_vaultIncentivesController, address(0), bytes32(0));
    }

    // FOUNDRY_PROFILE=vaults_tests forge test -vvv --ffi --mt test_claimRewardsAndDistribute
    function test_claimRewardsAndDistribute() public {
        address rewardToken1 = makeAddr("RewardToken1");
        address rewardToken2 = makeAddr("RewardToken2");

        uint256 amount1 = 1000;
        uint256 amount2 = 2000;

        bytes memory claimRewardsInput = abi.encodeWithSignature(
            "claimRewards(address)",
            address(_vaultIncentivesController)
        );

        IDistributionManager.AccruedRewards memory accruedReward1 = IDistributionManager.AccruedRewards({
            rewardToken: rewardToken1,
            programId: bytes32(uint256(1)),
            amount: amount1
        });

        IDistributionManager.AccruedRewards memory accruedReward2 = IDistributionManager.AccruedRewards({
            rewardToken: rewardToken2,
            programId: bytes32(uint256(2)),
            amount: amount2
        });

        IDistributionManager.AccruedRewards[] memory accruedRewards = new IDistributionManager.AccruedRewards[](2);
        accruedRewards[0] = accruedReward1;
        accruedRewards[1] = accruedReward2;

        bytes memory claimRewardsReturnData = abi.encode(accruedRewards);

        vm.mockCall(_siloIncentivesController, claimRewardsInput, claimRewardsReturnData);
        vm.expectCall(_siloIncentivesController, claimRewardsInput);

        bytes memory immediateDistributionInput1 = abi.encodeWithSelector(
            ISiloIncentivesController.immediateDistribution.selector,
            rewardToken1,
            amount1
        );

        bytes memory immediateDistributionInput2 = abi.encodeWithSelector(
            ISiloIncentivesController.immediateDistribution.selector,
            rewardToken2,
            amount2
        );

        vm.mockCall(_vaultIncentivesController, immediateDistributionInput1, abi.encode(accruedReward1.programId));
        vm.mockCall(_vaultIncentivesController, immediateDistributionInput2, abi.encode(accruedReward2.programId));

        vm.expectCall(_vaultIncentivesController, immediateDistributionInput1);
        vm.expectCall(_vaultIncentivesController, immediateDistributionInput2);

        incentivesControllerCL.claimRewardsAndDistribute();
    }
}
