// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";

import {ISiloIncentivesControllerFactory} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {SiloIncentivesControllerFactoryDeploy} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";

import {MintableToken} from "../../_common/MintableToken.sol";
import {CantinaTicket} from "./CantinaTicket.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc CantinaTicket195
*/
contract CantinaTicket195 is CantinaTicket {
    SiloIncentivesControllerCompatible internal _controller;

    address internal _owner = makeAddr("Owner");
    address internal _notifier;
    MintableToken internal _rewardToken;

    uint256 internal constant _PRECISION = 10 ** 18;
    uint256 internal constant _TOTAL_SUPPLY = 1000e18;
    string internal constant _PROGRAM_NAME = "Test";
    string internal constant _PROGRAM_NAME_2 = "Test2";

    function setUp() public override {
        super.setUp();

        _rewardToken = new MintableToken(18);
        _notifier = address(new ERC20Mock());

        _rewardToken.setOnDemand(true);
        token0.setOnDemand(true);

        SiloIncentivesControllerFactoryDeploy deployer = new SiloIncentivesControllerFactoryDeploy();
        deployer.disableDeploymentsSync();

        ISiloIncentivesControllerFactory factory = deployer.run();

        _controller = SiloIncentivesControllerCompatible(factory.create(_owner, _notifier, _notifier, bytes32(0)));

        assertTrue(
            factory.isSiloIncentivesController(address(_controller)), "expected controller created in factory"
        );
    }

    function test_double_claim_rewards() public {
        address user1 = address(this);

        // Set a nonzero emission rate so rewards accrue over time.
        uint256 emissionPerSecond = 1e6;
        // Create an incentives program with a long enough distribution period.
        vm.prank(_controller.owner());
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(_rewardToken),
                distributionEnd: uint40(block.timestamp + 200),
                emissionPerSecond: uint104(emissionPerSecond)
            })
        );

        // Initially, the rewards balance for user1 should be zero.
        assertEq(_controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "no rewards initially");

        // User1 deposits tokens into silo0.
        silo0.deposit(100e18, user1);
        assertEq(silo0.balanceOf(user1), 100_000e18, "expect deposit");

        // Warp time forward to allow rewards to accrue.
        vm.warp(block.timestamp + 50);

        // Retrieve the rewards balance before any claim.
        _controller.getRewardsBalance(user1, _PROGRAM_NAME);
        // At this point, rewards should roughly equal emissionPerSecond * 50 (subject to scaling factors).

        // User1 makes the first claim.
        vm.prank(user1);
        _controller.claimRewards(user1);

        uint256 balanceAfterFirstClaim = _rewardToken.balanceOf(user1);

        // Warp forward an additional 10 seconds.
        vm.warp(block.timestamp + 10);

        // User1 makes a second claim.
        vm.prank(user1);
        _controller.claimRewards(user1);

        uint256 balanceAfterSecondClaim = _rewardToken.balanceOf(user1);

        // Calculate the rewards credited during the second claim.
        uint256 additionalReward = balanceAfterSecondClaim - balanceAfterFirstClaim;
        assertEq(additionalReward, 0, "Double claim rewards detected if not zero");

        // Under correct behavior (i.e. if unclaimed rewards were properly cleared),
        // the additional rewards should only cover the extra 10 seconds:
        emissionPerSecond * 10;

        // If the vulnerability is present, then unclaimed rewards from the first claim remain,
        // leading to a second claim that provides more than the expected additional rewards.
        // assertGt(additionalReward, expectedAdditionalReward, "Double claim rewards detected"); OFF! no additional
    }
}
