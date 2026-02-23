// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";

import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {SiloIncentivesControllerCL} from "../../../contracts/incentives/claiming-logics/SiloIncentivesControllerCL.sol";

import {INotificationReceiver} from "../../../contracts/interfaces/INotificationReceiver.sol";
import {IntegrationTest} from "../helpers/IntegrationTest.sol";
import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";

import {CAP} from "../helpers/BaseTest.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc VaultRewardsIntegrationTest -vvv
*/
contract VaultRewardsIntegrationSetup is IntegrationTest {
    MintableToken reward1 = new MintableToken(18);

    ISiloIncentivesController siloIncentivesController;
    ISiloIncentivesController vaultIncentivesController;
    IVaultIncentivesModule vaultIncentivesModule;

    function setUp() public virtual override {
        super.setUp();

        vaultIncentivesModule = vault.INCENTIVES_MODULE();
        assertTrue(address(vaultIncentivesModule) != address(0), "empty vaultIncentivesModule");

        _setCap(allMarkets[0], _cap());
        _setCap(allMarkets[1], _cap());
        _setCap(allMarkets[2], _cap());

        reward1.setOnDemand(true);

        vaultIncentivesController = new SiloIncentivesControllerCompatible(address(this), address(vault), address(vault));
        vm.label(address(vaultIncentivesController), "VaultIncentivesController");

        // SiloIncentivesController is per silo
        siloIncentivesController = new SiloIncentivesControllerCompatible(
            address(this), address(partialLiquidation), address(silo1)
        );

        // set SiloIncentivesController as gauge for hook
        vm.prank(Ownable(address(partialLiquidation)).owner());
        IGaugeHookReceiver(address(partialLiquidation)).setGauge(
            ISiloIncentivesController(address(siloIncentivesController)), IShareToken(address(silo1))
        );

        _sortSupplyQueueIdleLast();
        assertEq(address(vault.supplyQueue(0)), address(silo1), "supplyQueue[0] == silo1");

        (, uint24 hooksAfter) = IGaugeHookReceiver(address(partialLiquidation)).hookReceiverConfig(address(silo1));
        assertEq(hooksAfter, Hook.COLLATERAL_TOKEN | Hook.SHARE_TOKEN_TRANSFER, "hook after");
    }

    function _cap() internal view virtual returns (uint256) {
        return CAP;
    }

    function _setupIncentives() internal {
        vm.prank(OWNER);
        vaultIncentivesModule.addNotificationReceiver(INotificationReceiver(address(vaultIncentivesController)));

        SiloIncentivesControllerCL cl = new SiloIncentivesControllerCL(
            address(vaultIncentivesController), address(siloIncentivesController)
        );

        vm.prank(OWNER);
        vaultIncentivesModule.submitIncentivesClaimingLogic(IERC4626(address(silo1)), cl);

        vm.warp(block.timestamp + vault.timelock() + 1);

        vm.prank(OWNER);
        vaultIncentivesModule.acceptIncentivesClaimingLogic(IERC4626(address(silo1)), cl);
    }
}
