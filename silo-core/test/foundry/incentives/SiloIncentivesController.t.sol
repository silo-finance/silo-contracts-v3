// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISiloIncentivesControllerFactory} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {SiloIncentivesControllerFactoryDeploy} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IDistributionManager} from "silo-core/contracts/incentives/interfaces/IDistributionManager.sol";
import {AddressUtilsLib} from "silo-core/contracts/lib/AddressUtilsLib.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloIncentivesControllerTest
*/
contract SiloIncentivesControllerTest is Test {
    SiloIncentivesControllerCompatible internal _controller;

    address internal _owner = makeAddr("Owner");
    address internal _notifier;
    address internal _rewardToken;
    ISiloIncentivesControllerFactory internal _factory;

    address internal user1 = makeAddr("User1");
    address internal user2 = makeAddr("User2");
    address internal user3 = makeAddr("User3");

    uint256 internal _PRECISION;
    uint256 internal constant _TOTAL_SUPPLY = 1000e18;
    string internal constant _PROGRAM_NAME = "Test";
    string internal constant _PROGRAM_NAME_2 = "Test2";

    event IncentivesProgramCreated(string name);
    event IncentivesProgramUpdated(string name);
    event ClaimerSet(address indexed user, address indexed claimer);

    function setUp() public {
        _rewardToken = address(new ERC20Mock());
        _notifier = address(new ERC20Mock());

        SiloIncentivesControllerFactoryDeploy deployer = new SiloIncentivesControllerFactoryDeploy();
        deployer.disableDeploymentsSync();

        _factory = deployer.run();

        _controller = SiloIncentivesControllerCompatible(_factory.create(_owner, _notifier, _notifier, bytes32(0)));

        assertTrue(
            _factory.isSiloIncentivesController(address(_controller)), "expected controller created in factory"
        );

        _PRECISION = _controller.TEN_POW_PRECISION();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getProgramName -vv
    */
    function test_getProgramName() public view {
        bytes32 b1 = bytes32(abi.encodePacked("abc"));
        console2.logBytes32(b1);
        string memory programName = _controller.getProgramName(b1);
        assertEq(programName, "abc", "invalid programName");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_OwnableUnauthorizedAccount
    function test_createIncentivesProgram_OwnableUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));

        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(0),
                distributionEnd: 0,
                emissionPerSecond: 0
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_EmissionPerSecondTooHigh
    function test_createIncentivesProgram_EmissionPerSecondTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.EmissionPerSecondTooHigh.selector));

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(0),
                distributionEnd: 0,
                emissionPerSecond: 1e30
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_invalidDistributionEnd
    function test_createIncentivesProgram_invalidDistributionEnd() public {
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.InvalidDistributionEnd.selector));

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(0),
                distributionEnd: uint40(block.timestamp - 1),
                emissionPerSecond: 0
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_InvalidIncentivesProgramName
    function test_createIncentivesProgram_InvalidIncentivesProgramName() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.InvalidIncentivesProgramName.selector));

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: "",
                rewardToken: address(0),
                distributionEnd: uint40(block.timestamp),
                emissionPerSecond: 0
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_InvalidRewardToken
    function test_createIncentivesProgram_InvalidRewardToken() public {
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.InvalidRewardToken.selector));

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: address(0),
                distributionEnd: uint40(block.timestamp),
                emissionPerSecond: 0
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_tooLongProgramName
    function test_createIncentivesProgram_tooLongProgramName() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.TooLongProgramName.selector));

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp + 1000),
                emissionPerSecond: 1000e18
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createIncentivesProgram_Success
    function test_createIncentivesProgram_Success() public {
        ERC20Mock(_notifier).mint(address(this), _TOTAL_SUPPLY);

        uint104 emissionPerSecond = 1000e18;
        uint256 distributionEnd = block.timestamp + 1000;

        IDistributionManager.IncentiveProgramDetails memory detailsBefore =
            _controller.incentivesProgram(_PROGRAM_NAME);

        vm.expectEmit(true, true, true, true);
        emit IncentivesProgramCreated(_PROGRAM_NAME);

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(distributionEnd),
                emissionPerSecond: emissionPerSecond
            })
        );

        IDistributionManager.IncentiveProgramDetails memory details = _controller.incentivesProgram(_PROGRAM_NAME);

        uint256 lastUpdateTimestamp =
            detailsBefore.lastUpdateTimestamp == 0 ? block.timestamp : detailsBefore.lastUpdateTimestamp;

        uint256 expectedIndex =
            emissionPerSecond * (block.timestamp - lastUpdateTimestamp) * _PRECISION / _TOTAL_SUPPLY;

        assertEq(details.rewardToken, _rewardToken, "invalid rewardToken");
        assertEq(details.distributionEnd, distributionEnd, "invalid distributionEnd");
        assertEq(details.emissionPerSecond, emissionPerSecond, "invalid emissionPerSecond");
        assertEq(details.lastUpdateTimestamp, block.timestamp, "invalid lastUpdateTimestamp");
        assertEq(details.index, expectedIndex, "invalid index");

        string[] memory programsNames = new string[](1);
        programsNames[0] = _PROGRAM_NAME;
        assertEq(_controller.getAllProgramsNames(), programsNames);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_updateIncentivesProgram_IncentivesProgramAlreadyExists
    function test_updateIncentivesProgram_IncentivesProgramAlreadyExists() public {
        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp + 1000),
                emissionPerSecond: 1000e18
            })
        );

        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.IncentivesProgramAlreadyExists.selector));

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp + 1000),
                emissionPerSecond: 1000e18
            })
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_updateIncentivesProgram_EmissionPerSecondTooHigh
    function test_updateIncentivesProgram_EmissionPerSecondTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.EmissionPerSecondTooHigh.selector));

        vm.prank(_owner);
        _controller.updateIncentivesProgram(_PROGRAM_NAME, uint40(block.timestamp + 1000), 1e30);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_updateIncentivesProgram_InvalidDistributionEnd
    function test_updateIncentivesProgram_InvalidDistributionEnd() public {
        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp + 1000),
                emissionPerSecond: 1000e18
            })
        );

        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.InvalidDistributionEnd.selector));

        vm.prank(_owner);
        _controller.updateIncentivesProgram(_PROGRAM_NAME, uint40(block.timestamp - 1), 1000e18);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_updateIncentivesProgram_IncentivesProgramNotFound
    function test_updateIncentivesProgram_IncentivesProgramNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.IncentivesProgramNotFound.selector));

        vm.prank(_owner);
        _controller.updateIncentivesProgram(_PROGRAM_NAME, uint40(block.timestamp + 1000), 1000e18);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_handleAction_for_to
    function test_handleAction_for_to() public {
        ERC20Mock(_rewardToken).mint(address(_controller), 20e18);

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp),
                emissionPerSecond: 1e18
            })
        );

        uint256 clockStart = block.timestamp;

        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);
        uint256 totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user1,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        vm.prank(_owner);
        _controller.setDistributionEnd(_PROGRAM_NAME, uint40(clockStart + 20));

        assertEq(_controller.getDistributionEnd(_PROGRAM_NAME), clockStart + 20, "invalid distributionEnd");

        vm.warp(block.timestamp + 10);

        vm.prank(user1);
        ERC20Mock(_notifier).transfer(user2, user1Deposit1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: user1,
            _senderBalance: 0,
            _recipient: user2,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        vm.warp(block.timestamp + 10);

        // user1 claim rewards
        vm.prank(user1);
        _controller.claimRewards(user1);
        // user2 claim rewards
        vm.prank(user2);
        _controller.claimRewards(user2);

        assertEq(ERC20Mock(_rewardToken).balanceOf(user1), 10e18, "invalid user1 balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(user2), 10e18, "invalid user2 balance");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_setDistributionEnd_Success
    function test_setDistributionEnd_Success() public {
        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp + 100),
                emissionPerSecond: 1e18
            })
        );

        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);
        uint256 totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user1,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        IDistributionManager.IncentiveProgramDetails memory details = _controller.incentivesProgram(_PROGRAM_NAME);

        uint256 lastUpdateTimestamp = details.lastUpdateTimestamp;
        assertEq(lastUpdateTimestamp, block.timestamp, "invalid lastUpdateTimestamp");

        vm.warp(block.timestamp + 100);

        vm.prank(_owner);
        _controller.setDistributionEnd(_PROGRAM_NAME, uint40(block.timestamp));

        details = _controller.incentivesProgram(_PROGRAM_NAME);
        uint256 indexBefore = details.index;
        details = _controller.incentivesProgram(_PROGRAM_NAME);
        assertEq(details.lastUpdateTimestamp, block.timestamp, "invalid lastUpdateTimestamp");

        vm.warp(block.timestamp + 100);

        vm.prank(_owner);
        _controller.setDistributionEnd(_PROGRAM_NAME, uint40(block.timestamp));

        details = _controller.incentivesProgram(_PROGRAM_NAME);
        assertEq(details.lastUpdateTimestamp, block.timestamp, "invalid lastUpdateTimestamp");
        assertEq(details.index, indexBefore, "invalid index");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_decrease_rewards
    function test_decrease_rewards() public {
        ERC20Mock(_rewardToken).mint(address(_controller), 11e18);

        uint104 initialEmissionPerSecond = 1e18;

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(block.timestamp),
                emissionPerSecond: initialEmissionPerSecond
            })
        );

        uint256 clockStart = block.timestamp;

        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);
        uint256 totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user1,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        uint40 newDistributionEnd = uint40(clockStart + 20);

        vm.prank(_owner);
        _controller.setDistributionEnd(_PROGRAM_NAME, newDistributionEnd);

        vm.warp(block.timestamp + 10);

        vm.prank(_owner);
        _controller.updateIncentivesProgram({
            _incentivesProgram: _PROGRAM_NAME,
            _distributionEnd: newDistributionEnd,
            _emissionPerSecond: uint104(initialEmissionPerSecond / 10)
        });

        // user2 deposit 100
        uint256 user2Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user2, user2Deposit1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user2,
            _recipientBalance: user2Deposit1,
            _totalSupply: totalSupply,
            _amount: user2Deposit1
        });

        vm.warp(block.timestamp + 10);

        uint256 expectedRewardsUser1 = 105e17;
        uint256 expectedRewardsUser2 = 5e17;

        uint256 rewards = _controller.getRewardsBalance(user1, _PROGRAM_NAME);
        assertEq(rewards, expectedRewardsUser1, "invalid user1 rewards");

        rewards = _controller.getRewardsBalance(user2, _PROGRAM_NAME);
        assertEq(rewards, expectedRewardsUser2, "invalid user2 rewards");

        vm.prank(user1);
        _controller.claimRewards(user1);
        vm.prank(user2);
        _controller.claimRewards(user2);

        assertEq(ERC20Mock(_rewardToken).balanceOf(user1), expectedRewardsUser1, "invalid user1 balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(user2), expectedRewardsUser2, "invalid user2 balance");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_updateIncentivesProgram_Success
    */
    function test_updateIncentivesProgram_Success() public {
        ERC20Mock(_notifier).mint(address(this), _TOTAL_SUPPLY);

        uint40 distributionEnd = uint40(block.timestamp + 1000);
        uint104 emissionPerSecond = 1000e18;

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: distributionEnd,
                emissionPerSecond: emissionPerSecond
            })
        );

        IDistributionManager.IncentiveProgramDetails memory detailsBefore =
            _controller.incentivesProgram(_PROGRAM_NAME);

        assertEq(detailsBefore.emissionPerSecond, emissionPerSecond, "invalid emissionPerSecond");
        assertEq(detailsBefore.distributionEnd, distributionEnd, "invalid distributionEnd");

        vm.warp(block.timestamp + 1000);

        distributionEnd = uint40(block.timestamp + 2000);
        emissionPerSecond = 2000e18;

        vm.expectEmit(true, true, true, true);
        emit IncentivesProgramUpdated(_PROGRAM_NAME);

        vm.prank(_owner);
        _controller.updateIncentivesProgram(_PROGRAM_NAME, distributionEnd, emissionPerSecond);

        uint256 expectedIndex = detailsBefore.index
            + detailsBefore.emissionPerSecond * (block.timestamp - detailsBefore.lastUpdateTimestamp) * _PRECISION
                / _TOTAL_SUPPLY;

        IDistributionManager.IncentiveProgramDetails memory detailsAfter =
            _controller.incentivesProgram(_PROGRAM_NAME);

        assertEq(detailsAfter.index, expectedIndex, "invalid index");
        assertEq(detailsAfter.emissionPerSecond, emissionPerSecond, "invalid emissionPerSecond");
        assertEq(detailsAfter.distributionEnd, distributionEnd, "invalid distributionEnd");
        assertEq(detailsAfter.lastUpdateTimestamp, block.timestamp, "invalid lastUpdateTimestamp");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_afterTokenTransfer_OnlyNotifier
    function test_afterTokenTransfer_OnlyNotifier() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.OnlyNotifier.selector));

        _controller.afterTokenTransfer(address(0), 0, address(0), 0, 0, 0);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_afterTokenTransfer_ShouldNotRevert
    function test_afterTokenTransfer_ShouldNotRevert() public {
        vm.prank(_notifier);
        _controller.afterTokenTransfer(address(0), 0, address(0), 0, 0, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_afterTokenTransfer_Success
    */
    function test_afterTokenTransfer_Success() public {
        ERC20Mock(_notifier).mint(address(this), _TOTAL_SUPPLY);

        uint40 distributionEnd = uint40(block.timestamp + 30 days);
        uint104 emissionPerSecond = 100e18;

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: distributionEnd,
                emissionPerSecond: emissionPerSecond
            })
        );

        address recipient = makeAddr("Recipient");
        uint256 recipientBalance = 100e18;
        uint256 newTotalSupply = _TOTAL_SUPPLY + recipientBalance;
        uint256 amount = recipientBalance;

        ERC20Mock(_notifier).mint(recipient, recipientBalance);

        uint256 userDataBefore = _controller.getUserData(recipient, _PROGRAM_NAME);
        assertEq(userDataBefore, 0);

        vm.warp(block.timestamp + 1 days);

        vm.prank(_notifier);
        _controller.afterTokenTransfer(address(0), 0, recipient, recipientBalance, newTotalSupply, amount);

        IDistributionManager.IncentiveProgramDetails memory detailsAfter =
            _controller.incentivesProgram(_PROGRAM_NAME);

        uint256 userDataAfter = _controller.getUserData(recipient, _PROGRAM_NAME);

        uint256 expectedIndex = detailsAfter.index
            + detailsAfter.emissionPerSecond * (block.timestamp - detailsAfter.lastUpdateTimestamp) * _PRECISION
                / newTotalSupply;

        assertEq(expectedIndex, detailsAfter.index);
        assertEq(userDataAfter, expectedIndex);

        vm.warp(block.timestamp + 10 days);

        uint256 rewards = _controller.getRewardsBalance(recipient, _PROGRAM_NAME);

        expectedIndex = expectedIndex
            + detailsAfter.emissionPerSecond * (block.timestamp - detailsAfter.lastUpdateTimestamp) * _PRECISION
                / newTotalSupply;

        uint256 expectedRewards = recipientBalance * (expectedIndex - userDataAfter) / _PRECISION;
        expectedRewards += _controller.getUserUnclaimedRewards(recipient, _PROGRAM_NAME);

        assertEq(rewards, expectedRewards, "unexpected rewards");
        assertNotEq(rewards, 0);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_permissions
    function test_immediateDistribution_permissions() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.OnlyNotifier.selector));
        _controller.immediateDistribution(_rewardToken, 100e18);
    }

    // test scenario 1 for immediateDistribution
    //
    // distribute 0
    // user1 deposit 100
    // move time 1 month
    // distribute 1000
    // user2 deposit 100
    // move 100 days
    // distribute 1000
    // user3 deposit 100
    // claimRewards (user1 - 1500, user2 - 500, user3 - 0)
    //
    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_scenario_1_for_immediateDistribution
    function test_scenario_1_for_immediateDistribution() public {
        string memory programName = Strings.toHexString(_rewardToken);

        vm.prank(_notifier);
        bytes32 programId = _controller.immediateDistribution(_rewardToken, uint104(1));
        assertEq(_controller.getProgramName(programId), programName, "invalid programName for immediate distribution");

        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);
        uint256 totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user1,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        // move time 1 month
        vm.warp(block.timestamp + 30 days);

        // distribute 1000
        uint256 toDistribute = 1000e18;
        ERC20Mock(_rewardToken).mint(address(_controller), toDistribute);

        vm.prank(_notifier);
        programId = _controller.immediateDistribution(_rewardToken, uint104(toDistribute));
        assertEq(_controller.getProgramName(programId), programName, "program name should stay the same");

        // user2 deposit 100
        uint256 user2Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user2, user2Deposit1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user2,
            _recipientBalance: user2Deposit1,
            _totalSupply: totalSupply,
            _amount: user2Deposit1
        });

        // move 100 days
        vm.warp(block.timestamp + 100 days);

        // distribute 1000
        toDistribute = 1000e18;
        ERC20Mock(_rewardToken).mint(address(_controller), toDistribute);

        vm.prank(_notifier);
        programId = _controller.immediateDistribution(_rewardToken, uint104(toDistribute));
        assertEq(_controller.getProgramName(programId), programName, "program name should stay the same");

        // user3 deposit 100
        uint256 user3Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user3, user3Deposit1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user3,
            _recipientBalance: user3Deposit1,
            _totalSupply: totalSupply,
            _amount: user3Deposit1
        });

        uint256 expectedRewardsUser1 = 1500e18;
        uint256 expectedRewardsUser2 = 500e18;
        uint256 expectedRewardsUser3 = 0;

        uint256 rewards = _controller.getRewardsBalance(user1, programName);
        assertEq(rewards, expectedRewardsUser1, "invalid user1 balance before claim");

        rewards = _controller.getRewardsBalance(user2, programName);
        assertEq(rewards, expectedRewardsUser2, "invalid user2 balance before claim");

        rewards = _controller.getRewardsBalance(user3, programName);
        assertEq(rewards, expectedRewardsUser3, "invalid user3 balance before claim");

        // user1 claim rewards
        _claimRewards(user1, user1, programName);
        // user2 claim rewards
        _claimRewards(user2, user2, programName);
        // user3 claim rewards
        _claimRewards(user3, user3, programName);

        assertEq(ERC20Mock(_rewardToken).balanceOf(user1), expectedRewardsUser1, "invalid user1 balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(user2), expectedRewardsUser2, "invalid user2 balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(user3), expectedRewardsUser3, "invalid user3 balance");
    }

    // test scenario 2 for immediateDistribution
    //
    // distribute 0
    // user1 deposit 100
    // move time 1 month
    // distribute 1000
    // user2 deposit 100
    // distribute 900
    // user1 withdraw 100
    // move 100 days
    // distribute 100
    // user3 deposit 100
    // claimRewards (user1 - 1450, user2 - 550, user3 - 0)
    //
    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_scenario_2_for_immediateDistribution
    function test_scenario_2_for_immediateDistribution() public {
        string memory programName = Strings.toHexString(_rewardToken);

        vm.prank(_notifier);
        _controller.immediateDistribution(_rewardToken, uint104(1));

        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);
        uint256 totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user1,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        // move time 1 month
        vm.warp(block.timestamp + 30 days);

        // distribute 1000
        uint256 toDistribute = 1000e18;
        ERC20Mock(_rewardToken).mint(address(_controller), toDistribute);

        vm.prank(_notifier);
        _controller.immediateDistribution(_rewardToken, uint104(toDistribute));

        // user2 deposit 100
        uint256 user2Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user2, user2Deposit1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user2,
            _recipientBalance: user2Deposit1,
            _totalSupply: totalSupply,
            _amount: user2Deposit1
        });

        // move 100 days
        vm.warp(block.timestamp + 100 days);

        // distribute 900
        toDistribute = 900e18;
        ERC20Mock(_rewardToken).mint(address(_controller), toDistribute);

        vm.prank(_notifier);
        _controller.immediateDistribution(_rewardToken, uint104(toDistribute));

        // user1 withdraw 100
        uint256 user1Withdraw1 = 100e18;
        ERC20Mock(_notifier).burn(user1, user1Withdraw1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: user1,
            _senderBalance: user1Deposit1 - user1Withdraw1,
            _recipient: address(0),
            _recipientBalance: 0,
            _totalSupply: totalSupply,
            _amount: user1Withdraw1
        });

        // move 100 days
        vm.warp(block.timestamp + 100 days);

        // distribute 100
        toDistribute = 100e18;
        ERC20Mock(_rewardToken).mint(address(_controller), toDistribute);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.immediateDistribution(_rewardToken, uint104(toDistribute));

        // user3 deposit 100
        uint256 user3Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user3, user3Deposit1);
        totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user3,
            _recipientBalance: user3Deposit1,
            _totalSupply: totalSupply,
            _amount: user3Deposit1
        });

        uint256 expectedRewardsUser1 = 1450e18;
        uint256 expectedRewardsUser2 = 550e18;
        uint256 expectedRewardsUser3 = 0;

        uint256 rewards = _controller.getRewardsBalance(user1, programName);
        assertEq(rewards, expectedRewardsUser1);

        rewards = _controller.getRewardsBalance(user2, programName);
        assertEq(rewards, expectedRewardsUser2);

        rewards = _controller.getRewardsBalance(user3, programName);
        assertEq(rewards, expectedRewardsUser3);

        // user1 claim rewards
        _claimRewards(user1, user1, programName);
        // user2 claim rewards
        _claimRewards(user2, user2, programName);
        // user3 claim rewards
        _claimRewards(user3, user3, programName);

        assertEq(ERC20Mock(_rewardToken).balanceOf(user1), expectedRewardsUser1, "invalid user1 balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(user2), expectedRewardsUser2, "invalid user2 balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(user3), expectedRewardsUser3, "invalid user3 balance");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_createIncentivesProgram
    function test_immediateDistribution_createIncentivesProgram() public {
        string memory programName = Strings.toHexString(_rewardToken);

        vm.expectEmit(true, true, true, true);
        emit IncentivesProgramCreated(programName);

        vm.prank(_notifier);
        bytes32 programId = _controller.immediateDistribution(_rewardToken, 1e18);
        assertEq(_controller.getProgramName(programId), programName, "invalid programName for immediate distribution");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_doNotRevert_when_amount_is_0
    */
    function test_immediateDistribution_doNotRevert_when_amount_is_0() public {
        vm.prank(_notifier);
        bytes32 programId = _controller.immediateDistribution(_rewardToken, 0);
        assertEq(programId, bytes32(0), "programId should be 0");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_not_allowed_for_owner
    function test_immediateDistribution_not_allowed_for_owner() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.OnlyNotifier.selector));

        vm.prank(_owner);
        _controller.immediateDistribution(_rewardToken, 1e18);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_setClaimer_onlyOwner
    function test_setClaimer_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _controller.setClaimer(user1, address(this));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_setClaimer_zeroAddress
    function test_setClaimer_zeroAddress() public {
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.ZeroAddress.selector));
        _controller.setClaimer(address(0), address(this));

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.ZeroAddress.selector));
        _controller.setClaimer(user1, address(0));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_wrong_notifier
    function test_wrong_notifier() public {
        // vm.expectRevert(abi.encodeWithSelector(IDistributionManager.WrongDecimals.selector));
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.ZeroAddress.selector));
        SiloIncentivesControllerCompatible(_factory.create(_owner, address(0), address(0), bytes32(0)));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_setClaimer_success
    function test_setClaimer_success() public {
        vm.expectEmit(address(_controller));
        emit ClaimerSet(user1, address(this));

        vm.prank(_owner);
        _controller.setClaimer(user1, address(this));

        assertEq(_controller.getClaimer(user1), address(this), "invalid claimer");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_claimRewards_programNotFound
    function test_claimRewards_programNotFound() public {
        string[] memory programsNames = new string[](1);
        programsNames[0] = "Some other program";
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.IncentivesProgramNotFound.selector));
        _controller.claimRewards(user1, programsNames);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_claimRewardsOnBehalf_onlyAuthorizedClaimers
    function test_claimRewardsOnBehalf_onlyAuthorizedClaimers() public {
        string[] memory programsNames = new string[](1);
        programsNames[0] = _PROGRAM_NAME;
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.ClaimerUnauthorized.selector));
        _controller.claimRewardsOnBehalf(user1, user2, programsNames);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_claimRewardsOnBehalf_programNotFound
    function test_claimRewardsOnBehalf_programNotFound() public {
        vm.prank(_owner);
        _controller.setClaimer(user1, address(this));

        string[] memory programsNames = new string[](1);
        programsNames[0] = "Some other program";
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.IncentivesProgramNotFound.selector));
        _controller.claimRewardsOnBehalf(user1, user2, programsNames);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_claimRewardsOnBehalf_inputsValidation
    function test_claimRewardsOnBehalf_inputsValidation() public {
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.ZeroAddress.selector));
        _controller.setClaimer(address(0), address(this));

        vm.prank(_owner);
        _controller.setClaimer(user1, address(this));

        string[] memory programsNames = new string[](1);
        programsNames[0] = _PROGRAM_NAME;

        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.InvalidToAddress.selector));
        _controller.claimRewardsOnBehalf(user1, address(0), programsNames);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_claimRewardsOnBehalf_success
    function test_claimRewardsOnBehalf_success() public {
        ERC20Mock(_notifier).mint(address(this), _TOTAL_SUPPLY);

        uint40 distributionEnd = uint40(block.timestamp + 30 days);
        uint104 emissionPerSecond = 100e18;

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: distributionEnd,
                emissionPerSecond: emissionPerSecond
            })
        );

        vm.prank(_owner);
        _controller.setClaimer(user1, address(this));

        string[] memory programsNames = new string[](1);
        programsNames[0] = _PROGRAM_NAME;

        IDistributionManager.AccruedRewards[] memory accruedRewards =
            _controller.claimRewardsOnBehalf(user1, address(this), programsNames);

        assertEq(accruedRewards.length, 1, "expected 1 rewards and do not revert");
        assertEq(accruedRewards[0].amount, 0, "expected 0 rewards");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_claimRewards_toSomeoneElse
    */
    function test_claimRewards_toSomeoneElse() public {
        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);

        string memory programName = Strings.toHexString(_rewardToken);

        uint256 toDistribute = 1000e18;
        ERC20Mock(_rewardToken).mint(address(_controller), toDistribute);

        vm.expectEmit(true, true, true, true);
        emit ISiloIncentivesController.ImmediateDistribution(_rewardToken, bytes32(uint256(uint160(_rewardToken))), toDistribute);

        vm.prank(_notifier);
        _controller.immediateDistribution(_rewardToken, uint104(toDistribute));

        _claimRewards(user1, user2, programName);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_emissionPerSecond
    */
    function test_immediateDistribution_emissionPerSecond_fuzz(uint256 _toDistribute) public {
        vm.assume(_toDistribute > 0);
        _immediateDistribution_emissionPerSecond(_toDistribute);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_emissionPerSecond_max
    */
    function test_immediateDistribution_emissionPerSecond_max() public {
        uint256 user1Deposit = 100e18;
        uint256 maxEmissionPerSecond = Math.mulDiv(type(uint256).max, user1Deposit, _controller.TEN_POW_PRECISION());

        _immediateDistribution_emissionPerSecond(maxEmissionPerSecond - 1);
    }

    function _immediateDistribution_emissionPerSecond(uint256 _toDistribute) internal {
        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);

        string memory programName = Strings.toHexString(_rewardToken);

        ERC20Mock(_rewardToken).mint(address(_controller), _toDistribute);

        vm.expectEmit(true, true, true, true);
        emit ISiloIncentivesController.ImmediateDistribution(_rewardToken, bytes32(uint256(uint160(_rewardToken))), _toDistribute);

        vm.prank(_notifier);
        try _controller.immediateDistribution(_rewardToken, _toDistribute) {
            // ok
        } catch (bytes memory _err) {
            bytes4 emissionPerSecondOverflowSelector = IDistributionManager.EmissionForTimeDeltaOverflow.selector;
            bytes4 indexOverflowSelector = IDistributionManager.IndexOverflow.selector;
            bytes4 newIndexOverflowSelector = IDistributionManager.NewIndexOverflow.selector;

            if (bytes4(_err) != emissionPerSecondOverflowSelector && bytes4(_err) != indexOverflowSelector && bytes4(_err) != newIndexOverflowSelector) {
                console2.log("expected EmissionForTimeDeltaOverflow() or IndexOverflow() or NewIndexOverflow()");
                RevertLib.revertBytes(_err, string(""));
            } else {
                // OK, we expected above errors
                vm.assume(false);
            }
        }

        _claimRewards(user1, user1, programName);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_getRewardsBalance_DifferentRewardsTokens
    function test_getRewardsBalance_DifferentRewardsTokens() public {
        uint256 distributionEnd = block.timestamp + 100 days;
        uint104 emissionPerSecond = 1e18;

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(distributionEnd),
                emissionPerSecond: emissionPerSecond
            })
        );

        string[] memory programsNames = new string[](2);
        programsNames[0] = _PROGRAM_NAME;
        programsNames[1] = "Some other program";

        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.DifferentRewardsTokens.selector));
        _controller.getRewardsBalance(user1, programsNames);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_getRewardsBalance_success
    function test_getRewardsBalance_success() public {
        uint256 distributionEnd = block.timestamp + 100 days;
        uint104 emissionPerSecond = 1e18;

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME,
                rewardToken: _rewardToken,
                distributionEnd: uint40(distributionEnd),
                emissionPerSecond: emissionPerSecond
            })
        );

        vm.prank(_owner);
        _controller.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: _PROGRAM_NAME_2,
                rewardToken: _rewardToken,
                distributionEnd: uint40(distributionEnd),
                emissionPerSecond: emissionPerSecond
            })
        );

        // user1 deposit 100
        uint256 user1Deposit1 = 100e18;
        ERC20Mock(_notifier).mint(user1, user1Deposit1);
        uint256 totalSupply = ERC20Mock(_notifier).totalSupply();

        vm.prank(_notifier);
        _controller.afterTokenTransfer({
            _sender: address(0),
            _senderBalance: 0,
            _recipient: user1,
            _recipientBalance: user1Deposit1,
            _totalSupply: totalSupply,
            _amount: user1Deposit1
        });

        vm.warp(block.timestamp + 1 days);

        uint256 expectedRewards = 172800000000000000000000;

        string[] memory programsNames = new string[](2);
        programsNames[0] = _PROGRAM_NAME;
        programsNames[1] = _PROGRAM_NAME_2;

        uint256 rewards = _controller.getRewardsBalance(user1, programsNames);
        assertEq(rewards, expectedRewards, "expected rewards");

        string[] memory programsNames2 = new string[](1);
        programsNames2[0] = _PROGRAM_NAME_2;

        rewards = _controller.getRewardsBalance(user1, programsNames2);
        assertEq(rewards, expectedRewards / 2, "expected rewards / 2");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_setDistributionEnd_invalidDistributionEnd
    function test_setDistributionEnd_invalidDistributionEnd() public {
        vm.expectRevert(abi.encodeWithSelector(ISiloIncentivesController.InvalidDistributionEnd.selector));
        vm.prank(_owner);
        _controller.setDistributionEnd(_PROGRAM_NAME, uint40(block.timestamp - 1));
    }

    // FOUNDRY_PROFILE=core_test forge test --ffi --mt test_rescueRewards_onlyOwner -vvv
    function test_rescueRewards_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _controller.rescueRewards(_rewardToken);
    }

    // FOUNDRY_PROFILE=core_test forge test --ffi --mt test_rescueRewards_success -vvv
    function test_rescueRewards_success() public {
        uint256 amount = 1000e18;
        ERC20Mock(_rewardToken).mint(address(_controller), amount);

        assertEq(ERC20Mock(_rewardToken).balanceOf(address(_controller)), amount, "expected max balance");

        vm.prank(_owner);
        _controller.rescueRewards(_rewardToken);

        assertEq(ERC20Mock(_rewardToken).balanceOf(address(_controller)), 0, "to have no balance");
        assertEq(ERC20Mock(_rewardToken).balanceOf(_owner), amount, "owner must have max balance");
    }

    // FOUNDRY_PROFILE=core-test forge test -vvv --ffi --mt test_getProgramId_InvalidIncentivesProgramName
    function test_getProgramId_InvalidIncentivesProgramName() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.InvalidIncentivesProgramName.selector));
        _controller.getProgramId("");

        vm.expectRevert(abi.encodeWithSelector(IDistributionManager.InvalidIncentivesProgramName.selector));
        _controller.getProgramId("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz");
    }

    // FOUNDRY_PROFILE=core-test forge test -vvv --ffi --mt test_getProgramId_InvalidAddressString
    function test_getProgramId_InvalidAddressString() public {
        vm.expectRevert(abi.encodeWithSelector(AddressUtilsLib.InvalidAddressString.selector));
        _controller.getProgramId("0xxx34567890123456789012345678901234567890");
    }

    // FOUNDRY_PROFILE=core-test forge test -vvv --ffi --mt test_getProgramId_success
    function test_getProgramId_success() public view {
        bytes32 programId = _controller.getProgramId(_PROGRAM_NAME);
        assertEq(programId, bytes32(abi.encodePacked(_PROGRAM_NAME)), "invalid string conversion");

        string memory addressAsString = Strings.toHexString(_rewardToken);
        bytes32 programId2 = _controller.getProgramId(addressAsString);

        bytes32 addressAsBytes32 = bytes32(uint256(uint160(_rewardToken)));
        assertEq(programId2, addressAsBytes32, "invalid address conversion");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_immediateDistribution_programName_getter
    */
    function test_immediateDistribution_programName_getter() public {
        string memory programName = Strings.toHexString(_rewardToken);

        vm.prank(_notifier);
        bytes32 programId = _controller.immediateDistribution(_rewardToken, uint104(1));
        assertEq(_controller.getProgramName(programId), programName, "invalid programName for immediate distribution");

        string[] memory programsNames = _controller.getAllProgramsNames();

        assertEq(programsNames[0], programName, "wrong conversion of programName");

        emit log_named_address("_rewardToken", _rewardToken);
        emit log_named_string("programsNames[0]", programsNames[0]);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_programsNames_getter
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_programsNames_getter(address _token, string memory _programName) public {
        vm.assume(_token != address(0));
        vm.assume(bytes(_programName).length > 0 && bytes(_programName).length <= 32);

        DistributionTypes.IncentivesProgramCreationInput memory input;

        input = DistributionTypes.IncentivesProgramCreationInput({
            name: _programName,
            rewardToken: _token,
            emissionPerSecond: 1e6,
            distributionEnd: uint40(block.timestamp + 1)
        });

        // create program
        vm.prank(_owner);
        _controller.createIncentivesProgram(input);

        // do distribution (it should create program)
        vm.prank(_notifier);
        bytes32 programId = _controller.immediateDistribution(_token, uint104(1));
        string memory programName = Strings.toHexString(_token);

        assertEq(_controller.getProgramName(programId), programName, "invalid programName for immediate distribution");

        string[] memory programsNames = _controller.getAllProgramsNames();
        assertEq(programsNames.length, 2, "expected 2 programs");

        assertEq(programsNames[0], _programName, "expected programName");

        // check immediateDistribution program name
        // 1. It should be a string representation of the `_token`
        string memory expectedProgramName = Strings.toHexString(_token);
        assertEq(programsNames[1], expectedProgramName, "_token programName string");
        // 2. Conversion from the string to address should result in the `_token`
        address programAddress = AddressUtilsLib.fromHexString(programsNames[1]);
        assertEq(programAddress, _token, "_token programName address");
    }

    function _claimRewards(address _user, address _to, string memory _programName) internal {
        uint256 snapshotId = vm.snapshotState();

        vm.prank(_user);
        IDistributionManager.AccruedRewards[] memory accruedRewards1 = _controller.claimRewards(_to);

        vm.revertToState(snapshotId);

        string[] memory programsNames = new string[](1);
        programsNames[0] = _programName;

        vm.prank(_user);
        IDistributionManager.AccruedRewards[] memory accruedRewards2 = _controller.claimRewards(_to, programsNames);

        bytes32 rewards1 = keccak256(abi.encode(accruedRewards1));
        bytes32 rewards2 = keccak256(abi.encode(accruedRewards2));

        assertTrue(rewards1 == rewards2, "expected rewards1 and rewards2 to be the same");
    }
}
