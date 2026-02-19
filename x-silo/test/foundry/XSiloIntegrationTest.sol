// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {IERC20} from "openzeppelin5/interfaces/IERC20.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {XSiloAndStreamDeploy} from "x-silo/deploy/XSiloAndStreamDeploy.s.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {XSilo} from "x-silo/contracts/XSilo.sol";
import {Stream} from "x-silo/contracts/modules/Stream.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";
import {INotificationReceiver} from "silo-vaults/contracts/interfaces/INotificationReceiver.sol";
import {SiloIncentivesControllerFactoryDeploy} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";

import {
    ISiloIncentivesControllerFactory
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";

/*
 FOUNDRY_PROFILE=x_silo forge test --ffi --mc XSiloIntegrationTest -vv
*/
contract XSiloIntegrationTest is Test {
    using SafeCast for uint256;
    address public constant SILO_WHALE = 0xE641Dca2E131FA8BFe1D7931b9b040e3fE0c5BDc;
    address public constant USDC_WHALE = 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6;

    ISiloIncentivesControllerFactory public siloIncentivesControllerFactory;
    ISiloIncentivesController public controller;

    XSilo public xSilo;
    Stream public stream;

    IERC20 public siloTokenV2;
    IERC20 public usdcToken;
    address public dao;

    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant INCENTIVE_DURATION = 1 hours;
    uint256 public distributionEnd;

    uint256 userInitialSiloBalance;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 33001840);

        XSiloAndStreamDeploy deploy = new XSiloAndStreamDeploy();
        deploy.disableDeploymentsSync();
        (xSilo, stream) = deploy.run();

        siloTokenV2 = IERC20(AddrLib.getAddress(AddrKey.SILO_TOKEN_V2));
        usdcToken = IERC20(AddrLib.getAddress(AddrKey.USDC_E));
        dao = AddrLib.getAddress(AddrKey.DAO);

        uint256 whaleBalance = siloTokenV2.balanceOf(SILO_WHALE);
        assertGt(whaleBalance, 1e18, "expect SILO_WHALE to have tokens");
        emit log_named_address("usdcToken", address(usdcToken));

        userInitialSiloBalance = whaleBalance / 10;

        vm.startPrank(SILO_WHALE);
        siloTokenV2.transfer(user1, userInitialSiloBalance);
        siloTokenV2.transfer(user2, userInitialSiloBalance);
        siloTokenV2.transfer(dao, userInitialSiloBalance);
        vm.stopPrank();

        SiloIncentivesControllerFactoryDeploy factoryDeploy = new SiloIncentivesControllerFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();
        siloIncentivesControllerFactory = ISiloIncentivesControllerFactory(address(factoryDeploy.run()));

        distributionEnd = block.timestamp + INCENTIVE_DURATION;

        vm.label(user1, "user1");
        vm.label(user2, "user2");

        controller = ISiloIncentivesController(
            siloIncentivesControllerFactory.create(dao, address(xSilo), address(xSilo), bytes32(0))
        );

        vm.label(address(controller), "SiloIncentivesController");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test --ffi --mt test_xSiloDeposit -vv

    Test scenario:
     - stream configuration (we have rewards)
     - silo incentives controller configuration (we have more rewards)
     - user1 deposits
     - user2 deposits
     - time passes
     - claim rewards
     - user1 withdraws half of his deposit
     - time passes
     - claim rewards
     - user1 withdraws all
     - user2 withdraws all
    */
    function test_xSiloDepositIncentivesWithdraw() public {
        _streamConfiguration();
        _siloIncentivesControllerConfiguration();
        _userDepositAllSiloBalance(user1);
        _userDepositAllSiloBalance(user2);
        vm.warp(block.timestamp + INCENTIVE_DURATION);
        _userRedeemSilo(user1);
        _userRedeemSilo(user2);
        vm.warp(block.timestamp + xSilo.maxRedeemDuration());
        _finalizeRedeem(user1);
        _finalizeRedeem(user2);

        // ensure we received more as we stream rewards
        assertGt(siloTokenV2.balanceOf(user1), userInitialSiloBalance, "User1 balance not updated");
        assertGt(siloTokenV2.balanceOf(user2), userInitialSiloBalance, "User2 balance not updated");

        assertEq(usdcToken.balanceOf(user1), 0, "User1 should not have any USDC");
        assertEq(usdcToken.balanceOf(user2), 0, "User2 should not have any USDC");

        // claim rewards
        vm.prank(user1);
        controller.claimRewards(user1);

        vm.prank(user2);
        controller.claimRewards(user2);

        assertNotEq(usdcToken.balanceOf(user1), 0, "User1 should have some USDC");
        assertNotEq(usdcToken.balanceOf(user2), 0, "User2 should have some USDC");
    }

    function _streamConfiguration() internal {
        uint256 emissionPerSecond = 1e18;

        vm.prank(dao);
        stream.setEmissions(emissionPerSecond, distributionEnd);

        vm.prank(dao);
        siloTokenV2.transfer(address(stream), INCENTIVE_DURATION * emissionPerSecond);
    }

    function _siloIncentivesControllerConfiguration() internal {
        DistributionTypes.IncentivesProgramCreationInput memory input;

        uint256 emissionPerSecond = 1e6;

        input = DistributionTypes.IncentivesProgramCreationInput({
            name: "test",
            rewardToken: address(usdcToken),
            emissionPerSecond: emissionPerSecond.toUint104(),
            distributionEnd: distributionEnd.toUint40()
        });

        vm.prank(dao);
        controller.createIncentivesProgram(input);

        assertGe(usdcToken.balanceOf(USDC_WHALE), INCENTIVE_DURATION * emissionPerSecond, "whale don't have tokens");
        vm.prank(USDC_WHALE);
        usdcToken.transfer(address(controller), INCENTIVE_DURATION * emissionPerSecond);

        vm.prank(dao);
        xSilo.setNotificationReceiver(INotificationReceiver(address(controller)), true);
    }

    function _userRedeemSilo(address _user) internal {
        uint256 balance = xSilo.balanceOf(_user);
        uint256 maxRedeemDuration = xSilo.maxRedeemDuration();
        
        vm.prank(_user);
        xSilo.redeemSilo(balance, maxRedeemDuration);
    }

    function _finalizeRedeem(address _user) internal {
        vm.prank(_user);
        xSilo.finalizeRedeem(0);
    }

    function _userDepositAllSiloBalance(address _user) internal {
        uint256 userBalance = siloTokenV2.balanceOf(_user);

        vm.prank(_user);
        siloTokenV2.approve(address(xSilo), userBalance);

        vm.prank(_user);
        uint256 shares = xSilo.deposit(userBalance, _user);

        uint256 expectedBalance = xSilo.convertToAssets(shares);

        assertEq(xSilo.balanceOf(_user), expectedBalance);
        assertEq(siloTokenV2.balanceOf(_user), 0);
    }
}
