// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {
    IBackwardsCompatibleGaugeLike
} from "silo-core/contracts/incentives/interfaces/IBackwardsCompatibleGaugeLike.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

contract GaugeHookReceiverReplaceTest is SiloLittleHelper, Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 64942204 - 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_gauge_replacement
    */
    function test_skip_gauge_replacement() public {
        ISiloConfig siloConfig = ISiloConfig(0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2);
        (address silo0,) = siloConfig.getSilos();

        address hook = IShareToken(silo0).hookSetup().hookReceiver;

        ISiloIncentivesController existingGauge =
            ISiloIncentivesController(0x89a10bFb6b57AD89b2270d80175914C517E547D9);

        string[] memory programNames = existingGauge.getAllProgramsNames();
        assertEq(programNames.length, 1, "expected 1 program for this simulation");

        console2.log("programName", programNames[0]);
        uint256 timeEnd = existingGauge.getDistributionEnd(programNames[0]);
        console2.log("distributionEnd", timeEnd);
        console2.log("already ended?", timeEnd < block.timestamp);

        address user = 0x3F2756FED3d151C80eb9C0e818F67B2d436102c6;

        uint256 balanceBefore = existingGauge.getRewardsBalance(user, programNames);
        emit log_named_decimal_uint("balance", balanceBefore, 18);

        vm.warp(1778233322);

        _ensureRewardDidNotChange(existingGauge, user, balanceBefore);

        vm.prank(Ownable(address(existingGauge)).owner());
        IBackwardsCompatibleGaugeLike(address(existingGauge)).killGauge();

        vm.startPrank(Ownable(hook).owner());
        IGaugeHookReceiver(hook).removeGauge(IShareToken(existingGauge.SHARE_TOKEN()));
        vm.stopPrank();

        vm.warp(block.timestamp + 100 days);

        ISilo silo = ISilo(IShareToken(existingGauge.SHARE_TOKEN()).silo());
        IERC20 asset = IERC20(silo.asset());
        uint256 amount = 1_000_000e18;

        console2.log("depositing %s %s", amount, IERC20Metadata(address(asset)).symbol());

        vm.startPrank(user);
        deal(address(asset), user, amount);
        asset.approve(address(silo), amount);
        silo.deposit(amount, user);
        vm.stopPrank();

        _ensureRewardDidNotChange(existingGauge, user, balanceBefore);
    }

    function _ensureRewardDidNotChange(
        ISiloIncentivesController _existingGauge,
        address _user,
        uint256 _expectedBalance
    ) internal view {
        string[] memory programNames = _existingGauge.getAllProgramsNames();
        assertEq(programNames.length, 1, "expected 1 program for this simulation");

        uint256 balance = _existingGauge.getRewardsBalance(_user, programNames);
        assertEq(balance, _expectedBalance, "reward is different than expected");
    }
}
