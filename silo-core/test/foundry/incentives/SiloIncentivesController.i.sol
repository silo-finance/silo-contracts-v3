// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IDistributionManager} from "silo-core/contracts/incentives/interfaces/IDistributionManager.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloConfigOverride} from "../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../_common/fixtures/SiloFixture.sol";

import {MintableToken} from "../_common/MintableToken.sol";
import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";

contract HookContract {
    SiloIncentivesControllerCompatible controller;
    MintableToken notifierToken;

    function setup(SiloIncentivesControllerCompatible _controller, MintableToken _notifierToken) public {
        controller = _controller;
        notifierToken = _notifierToken;
    }

    // notifier has to sum up total from all external contracts
    function totalSupply() external view returns (uint256) {
        return notifierToken.totalSupply();
    }

    // notifier has to sum up balances from all external contracts
    function balanceOf(address _user) external view returns (uint256) {
        return notifierToken.balanceOf(_user);
    }

    function hookReceiverConfig(address) external pure returns (uint24 hooksBefore, uint24 hooksAfter) {
        hooksBefore = 0;
        hooksAfter = uint24(Hook.SHARE_TOKEN_TRANSFER | Hook.COLLATERAL_TOKEN);
    }

    function afterAction(address, /* _silo */ uint256, /* _action */ bytes calldata _inputAndOutput) external {
        Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_inputAndOutput);

        controller.afterTokenTransfer(
            input.sender,
            input.senderBalance,
            input.recipient,
            input.recipientBalance,
            input.totalSupply,
            input.amount
        );
    }
}

/*
 FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloIncentivesControllerTest
*/
contract SiloIncentivesControllerIntegrationTest is SiloLittleHelper, Test {
    using SafeCast for uint256;
    SiloIncentivesControllerCompatible internal _controller;

    address internal _notifier;
    MintableToken internal _rewardToken;
    MintableToken internal _anotherRewardToken;
    HookContract hook;

    address internal user1 = makeAddr("User1");
    address internal user2 = makeAddr("User2");
    address internal user3 = makeAddr("User3");

    uint256 internal constant _PRECISION = 10 ** 18;
    string internal constant _PROGRAM_NAME = "Test";

    event IncentivesProgramCreated(bytes32 indexed incentivesProgramId);
    event IncentivesProgramUpdated(bytes32 indexed programId);
    event ClaimerSet(address indexed user, address indexed claimer);

    function setUp() public {
        hook = new HookContract();

        token0 = new MintableToken(18);
        token1 = new MintableToken(18);
        _rewardToken = new MintableToken(18);
        _anotherRewardToken = new MintableToken(18);

        vm.label(address(token0), "underlying0");
        vm.label(address(token1), "underlying1");
        vm.label(address(_rewardToken), "rewardToken");
        vm.label(address(_anotherRewardToken), "anotherRewardToken");

        token0.setOnDemand(true);
        token1.setOnDemand(true);
        _rewardToken.setOnDemand(true);
        _anotherRewardToken.setOnDemand(true);

        SiloFixture siloFixture = new SiloFixture();
        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.hookReceiver = address(hook);

        (, silo0, silo1,,,) = siloFixture.deploy_local(overrides);

        __init(token0, token1, silo0, silo1);

        _controller = new SiloIncentivesControllerCompatible(address(this), address(hook), address(silo0));
        hook.setup(_controller, MintableToken(address(silo0)));

        silo0.updateHooks();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_parallel_programs_1user -vvv
    */
    function test_scenario_parallel_programs_1user() public {
        _test_scenario_parallel_programs(false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_parallel_programs_2users -vvv
    */
    function test_scenario_parallel_programs_2users() public {
        _test_scenario_parallel_programs(true);
    }

    function _test_scenario_parallel_programs(bool _user2Deposit) internal {
        // it will not distribute less than 1e3, most likely because of decimals offset
        uint256 emissionPerSecond = 1e6;

        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(_rewardToken),
                distributionEnd: (block.timestamp + 100).toUint40(),
                emissionPerSecond: emissionPerSecond.toUint104()
            })
        );

        assertEq(_controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "[user1] no rewards without deposit");
        assertEq(_controller.getRewardsBalance(user2, _PROGRAM_NAME), 0, "[user2] no rewards without deposit");

        bytes memory data = abi.encodeWithSelector(
            ISiloIncentivesController.afterTokenTransfer.selector,
            address(0),
            0,
            user1,
            100e18 * SiloMathLib._DECIMALS_OFFSET_POW, // balance
            100e18 * SiloMathLib._DECIMALS_OFFSET_POW, // total
            100e18 * SiloMathLib._DECIMALS_OFFSET_POW // amount
        );

        vm.expectCall(address(_controller), data);

        silo0.deposit(100e18, user1);

        if (_user2Deposit) {
            silo0.deposit(100e18, user2);
        }

        vm.warp(block.timestamp + 50);

        assertEq(
            _controller.getRewardsBalance(user1, _PROGRAM_NAME),
            _user2Deposit ? emissionPerSecond * 50 / 2 : emissionPerSecond * 50,
            "[user1] some rewards after 1/2 period of time"
        );
        assertEq(
            _controller.getRewardsBalance(user2, _PROGRAM_NAME),
            _user2Deposit ? emissionPerSecond * 50 / 2 : 0,
            "[user2] some rewards after 1/2 period of time"
        );

        assertEq(_rewardToken.balanceOf(user1), 0, "[user1] rewards before");
        assertEq(_rewardToken.balanceOf(user2), 0, "[user2] rewards before");

        vm.expectEmit(true, true, true, false);
        emit IDistributionManager.UserIndexUpdated(user1, _PROGRAM_NAME, 0);

        vm.prank(user1);
        _controller.claimRewards(user1);

        assertEq(
            _rewardToken.balanceOf(user1),
            _user2Deposit ? emissionPerSecond * 50 / 2 : emissionPerSecond * 50,
            "[user1] rewards after"
        );

        assertEq(_rewardToken.balanceOf(user2), 0, "[user2] rewards after");

        uint256 immediateDistribution = 7e7;

        vm.startPrank(address(hook));
        _controller.immediateDistribution(address(_rewardToken), immediateDistribution);
        vm.stopPrank();

        vm.warp(block.timestamp + 50);

        uint256 expectedTotalRewards = emissionPerSecond * 100 + immediateDistribution;

        vm.prank(user1);
        _controller.claimRewards(user1);
        vm.prank(user2);
        _controller.claimRewards(user2);

        assertEq(
            _rewardToken.balanceOf(user1),
            _user2Deposit ? expectedTotalRewards / 2 : expectedTotalRewards,
            "[user1] rewards at the end"
        );

        assertEq(
            _rewardToken.balanceOf(user2),
            _user2Deposit ? expectedTotalRewards / 2 : 0,
            "[user2] rewards at the end"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_two_programs_1user -vvv
    */
    function test_scenario_two_programs_1user() public {
        _test_scenario_two_programs(false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_two_programs_2users -vvv
    */
    function test_scenario_two_programs_2users() public {
        _test_scenario_two_programs(true);
    }

    function _test_scenario_two_programs(bool _user2Deposit) internal {
        uint256 emissionPerSecond = 1e6;
        uint256 user1Deposit = 1e18;
        uint256 user2Deposit = _user2Deposit ? user1Deposit : 0;

        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(_rewardToken),
                distributionEnd: (block.timestamp + 100).toUint40(),
                emissionPerSecond: emissionPerSecond.toUint104() // it will not distribute less than 1e3, most likely because of offset
            })
        );

        assertEq(_controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "[user1] no rewards without deposit");
        assertEq(_controller.getRewardsBalance(user2, _PROGRAM_NAME), 0, "[user2] no rewards without deposit");

        silo0.deposit(user1Deposit, user1);

        if (user2Deposit > 0) {
            silo0.deposit(user2Deposit, user2);
        }

        vm.warp(block.timestamp + 50);

        assertEq(
            _controller.getRewardsBalance(user1, _PROGRAM_NAME),
            _user2Deposit ? emissionPerSecond * 50 / 2 : emissionPerSecond * 50,
            "[user1] full rewards"
        );
        assertEq(
            _controller.getRewardsBalance(user2, _PROGRAM_NAME),
            _user2Deposit ? emissionPerSecond * 50 / 2 : 0,
            "[user2] full rewards"
        );

        assertEq(_rewardToken.balanceOf(user1), 0, "[user1] rewards before");
        assertEq(_rewardToken.balanceOf(user2), 0, "[user2] rewards before");
        vm.prank(user1);
        _controller.claimRewards(user1);

        assertEq(
            _rewardToken.balanceOf(user1),
            _user2Deposit ? emissionPerSecond * 50 / 2 : emissionPerSecond * 50,
            "[user1] rewards after"
        );

        uint256 immediateDistribution = 7e7;

        vm.startPrank(address(hook));
        _controller.immediateDistribution(address(_rewardToken), immediateDistribution);
        vm.stopPrank();

        string[] memory names = new string[](2);
        names[0] = _PROGRAM_NAME;
        names[1] = Strings.toHexString(address(_rewardToken));

        assertEq(
            _controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "[user1] user1 claimed all from regular program"
        );

        assertEq(
            _controller.getRewardsBalance(user1, names),
            _user2Deposit ? immediateDistribution / 2 : immediateDistribution,
            "[user1] only immediate rewards"
        );

        assertEq(
            _controller.getRewardsBalance(user2, _PROGRAM_NAME),
            _user2Deposit ? (emissionPerSecond * 50) / 2 : 0,
            "[user2] only regular rewards"
        );
        assertEq(
            _controller.getRewardsBalance(user2, Strings.toHexString(address(_rewardToken))),
            _user2Deposit ? immediateDistribution / 2 : 0,
            "[user2] only immediate rewards"
        );

        assertEq(
            _controller.getRewardsBalance(user2, names),
            _user2Deposit ? (emissionPerSecond * 50 + immediateDistribution) / 2 : 0,
            "[user2] all rewards"
        );

        vm.warp(block.timestamp + 50);

        vm.prank(user1);
        _controller.claimRewards(user1);

        uint256 totalRewards = emissionPerSecond * 100 + immediateDistribution;

        assertEq(
            _rewardToken.balanceOf(user1),
            _user2Deposit ? totalRewards / 2 : totalRewards,
            "[user1] rewards at the end"
        );

        vm.prank(user2);
        _controller.claimRewards(user2);

        assertEq(_rewardToken.balanceOf(user2), _user2Deposit ? totalRewards / 2 : 0, "[user2] rewards at the end");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_two_different_programs_1user -vvv
    */
    function test_scenario_two_different_programs_1user() public {
        _test_scenario_two_different_programs(false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_two_different_programs_2users -vvv
    */
    function test_scenario_two_different_programs_2users() public {
        _test_scenario_two_different_programs(true);
    }

    function _test_scenario_two_different_programs(bool _user2Deposit) internal {
        uint256 emissionPerSecond = 1e6;
        uint256 user1Deposit = 1e18;
        uint256 user2Deposit = _user2Deposit ? user1Deposit : 0;

        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(_rewardToken),
                distributionEnd: (block.timestamp + 100).toUint40(),
                emissionPerSecond: emissionPerSecond.toUint104() // it will not distribute less than 1e3, most likely because of offset
            })
        );

        assertEq(_controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "[user1] no rewards without deposit");
        assertEq(_controller.getRewardsBalance(user2, _PROGRAM_NAME), 0, "[user2] no rewards without deposit");

        silo0.deposit(user1Deposit, user1);

        if (user2Deposit > 0) {
            silo0.deposit(user2Deposit, user2);
        }

        vm.warp(block.timestamp + 50);

        assertEq(
            _controller.getRewardsBalance(user1, _PROGRAM_NAME),
            _user2Deposit ? emissionPerSecond * 50 / 2 : emissionPerSecond * 50,
            "[user1] 1/2 rewards"
        );

        assertEq(
            _controller.getRewardsBalance(user2, _PROGRAM_NAME),
            _user2Deposit ? emissionPerSecond * 50 / 2 : 0,
            "[user2] 1/2 rewards"
        );

        assertEq(_rewardToken.balanceOf(user1), 0, "[user1] rewards before");
        assertEq(_rewardToken.balanceOf(user2), 0, "[user2] rewards before");
        vm.prank(user1);
        _controller.claimRewards(user1);

        assertEq(
            _rewardToken.balanceOf(user1),
            _user2Deposit ? emissionPerSecond * 50 / 2 : emissionPerSecond * 50,
            "[user1] rewards after"
        );

        uint256 immediateDistribution = 7e7;
        string memory immediateProgramName = Strings.toHexString(address(_anotherRewardToken));

        vm.startPrank(address(hook));
        _controller.immediateDistribution(address(_anotherRewardToken), immediateDistribution);
        vm.stopPrank();

        assertEq(
            _controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "[user1] no rewards, because it was claimed"
        );

        assertEq(
            _controller.getRewardsBalance(user1, immediateProgramName),
            _user2Deposit ? immediateDistribution / 2 : immediateDistribution,
            "[user1] immediate rewards"
        );

        assertEq(
            _controller.getRewardsBalance(user2, _PROGRAM_NAME),
            _user2Deposit ? (emissionPerSecond * 50) / 2 : 0,
            "[user2] normal rewards"
        );

        assertEq(
            _controller.getRewardsBalance(user2, immediateProgramName),
            _user2Deposit ? immediateDistribution / 2 : 0,
            "[user2] immediate rewards"
        );

        vm.warp(block.timestamp + 50);

        vm.prank(user1);
        _controller.claimRewards(user1);

        assertEq(
            _rewardToken.balanceOf(user1),
            _user2Deposit ? emissionPerSecond * 100 / 2 : emissionPerSecond * 100,
            "[user1] rewards at the end"
        );

        assertEq(
            _anotherRewardToken.balanceOf(user1),
            _user2Deposit ? immediateDistribution / 2 : immediateDistribution,
            "[user1] immediateDistribution rewards at the end"
        );

        vm.prank(user2);
        _controller.claimRewards(user2);

        assertEq(
            _rewardToken.balanceOf(user2),
            _user2Deposit ? emissionPerSecond * 100 / 2 : 0,
            "[user2] rewards at the end"
        );

        assertEq(
            _anotherRewardToken.balanceOf(user2),
            _user2Deposit ? immediateDistribution / 2 : 0,
            "[user2] immediateDistribution rewards at the end"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_scenario_single_program -vvv
    */
    function test_scenario_single_program() public {
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(_rewardToken),
                distributionEnd: (block.timestamp + 100).toUint40(),
                emissionPerSecond: uint104(0)
            })
        );

        assertEq(_controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "no rewards without deposit");

        silo0.deposit(100e18, user1);
        assertEq(silo0.balanceOf(user1), 100_000e18, "expect deposit");

        vm.warp(block.timestamp + 50);

        assertEq(_controller.getRewardsBalance(user1, _PROGRAM_NAME), 0, "NO rewards after 1/2 period of time");

        assertEq(_rewardToken.balanceOf(user1), 0, "rewards before");
        vm.prank(user1);
        _controller.claimRewards(user1);

        assertEq(_rewardToken.balanceOf(user1), 0, "rewards after");

        uint256 immediateDistribution = 33e7;

        vm.startPrank(address(hook));
        _controller.immediateDistribution(address(_rewardToken), immediateDistribution);
        vm.stopPrank();

        assertEq(
            _controller.getRewardsBalance(user1, Strings.toHexString(address(_rewardToken))),
            immediateDistribution,
            "immediate reward"
        );

        vm.warp(block.timestamp + 50);
        vm.prank(user1);
        _controller.claimRewards(user1);
        assertEq(_rewardToken.balanceOf(user1), immediateDistribution, "rewards at the end");
    }
}
