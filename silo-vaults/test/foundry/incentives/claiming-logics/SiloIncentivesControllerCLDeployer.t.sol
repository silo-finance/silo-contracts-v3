// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Forking} from "silo-oracles/test/foundry/_common/Forking.sol";
import {ISiloIncentivesControllerCLFactory} from "silo-vaults/contracts/interfaces/ISiloIncentivesControllerCLFactory.sol";
import {ISiloIncentivesControllerCLDeployer} from "silo-vaults/contracts/interfaces/ISiloIncentivesControllerCLDeployer.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {SiloIncentivesController} from "silo-core/contracts/incentives/SiloIncentivesController.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";
import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";
import {SiloIncentivesControllerCL} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCL.sol";
import {SiloIncentivesControllerCLDeployer} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCLDeployer.sol";
import {SiloIncentivesControllerCLDeployerDeploy} from "silo-vaults/deploy/SiloIncentivesControllerCLDeployerDeploy.s.sol";
import {INotificationReceiver} from "silo-vaults/contracts/interfaces/INotificationReceiver.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

// FOUNDRY_PROFILE=vaults_tests forge test -vvv --ffi --mc SiloIncentivesControllerCLDeployerTest
contract SiloIncentivesControllerCLDeployerTest is Forking {
    uint256 constant TEST_BLOCK = 23284167;

    address constant VAULT = 0xd80C3E98c9093b41645c07c2B6D956136F89559b;
    address constant MARKET = 0x322e1d5384aa4ED66AeCa770B95686271de61dc3;
    address constant VAULT_INCENTIVES_MODULE = 0xcA27aC93a51Ab7688cf877b518f11d0EdC70FB94;
    address constant VAULT_INCENTIVES_CONTROLLER = 0x4a03EcCB9f5247282fCA8F3EFCD8B3e3a84bDbAf;
    address constant MARKET_INCENTIVES_CONTROLLER = 0x2D3d269334485d2D876df7363e1A50b13220a7D8;

    address constant MARKET_WITHOUT_INCENTIVES = 0x558d6D6D53270ae8ba622daF123983D9F3c21792;

    ISiloIncentivesControllerCLFactory constant CL_FACTORY =
        ISiloIncentivesControllerCLFactory(0x8Ed9d9e689eecF67Dd4Cf603e45630F6264943a7);

    SiloIncentivesControllerCLDeployer clDeployer;

    constructor() Forking(BlockChain.SONIC) {
        initFork(TEST_BLOCK);

        SiloIncentivesControllerCLDeployerDeploy deploy = new SiloIncentivesControllerCLDeployerDeploy();
        deploy.disableDeploymentsSync();
        deploy.setCLFactory(CL_FACTORY);

        clDeployer = SiloIncentivesControllerCLDeployer(deploy.run());
    }

    function test_testingDataIsValid() public view {
        assertEq(address(ISiloVault(VAULT).INCENTIVES_MODULE()), VAULT_INCENTIVES_MODULE);

        assertEq(
            address(IVaultIncentivesModule(VAULT_INCENTIVES_MODULE).getNotificationReceivers()[0]),
            VAULT_INCENTIVES_CONTROLLER
        );

        ISiloConfig.ConfigData memory configData = ISilo(MARKET).config().getConfig(MARKET);

        address controllerFromHookReceiver =
            address(GaugeHookReceiver(configData.hookReceiver).configuredGauges(IShareToken(MARKET)));

        assertEq(MARKET_INCENTIVES_CONTROLLER, controllerFromHookReceiver);

        assertEq(SiloIncentivesController(VAULT_INCENTIVES_CONTROLLER).NOTIFIER(), VAULT);
        assertEq(SiloIncentivesController(MARKET_INCENTIVES_CONTROLLER).NOTIFIER(), configData.hookReceiver);
    }

    function test_constructor() public view {
        assertEq(address(clDeployer.CL_FACTORY()), address(CL_FACTORY));
    }

    function test_constructor_revertsForEmpty() public {
        vm.expectRevert(ISiloIncentivesControllerCLDeployer.EmptyCLFactory.selector);
        new SiloIncentivesControllerCLDeployer(ISiloIncentivesControllerCLFactory(address(0)));
    }

    function test_constructor_revertsForInvalid() public {
        vm.expectRevert();
        new SiloIncentivesControllerCLDeployer(ISiloIncentivesControllerCLFactory(MARKET));
    }

    function test_resolveSiloVaultIncentivesController() public view {
        ISiloIncentivesController controller = clDeployer.resolveSiloVaultIncentivesController(VAULT);
        assertEq(address(controller), VAULT_INCENTIVES_CONTROLLER);
    }

    function test_resolveSiloVaultIncentivesController_reverts() public {
        vm.prank(Ownable(VAULT_INCENTIVES_MODULE).owner());
        IVaultIncentivesModule(VAULT_INCENTIVES_MODULE).addNotificationReceiver(INotificationReceiver(address(1)));

        vm.expectRevert(ISiloIncentivesControllerCLDeployer.MoreThanOneSiloVaultNotificationReceiver.selector);
        clDeployer.resolveSiloVaultIncentivesController(VAULT);
    }

    function test_resolveMarketIncentivesController() public view {
        ISiloIncentivesController controller = clDeployer.resolveMarketIncentivesController(MARKET);
        assertEq(address(controller), MARKET_INCENTIVES_CONTROLLER);
    }

    function test_resolveMarketIncentivesController_reverts() public {
        vm.expectRevert(ISiloIncentivesControllerCLDeployer.UnderlyingMarketDoesNotHaveIncentives.selector);
        clDeployer.resolveMarketIncentivesController(MARKET_WITHOUT_INCENTIVES);
    }

    function test_createIncentivesControllerCL() public {
        SiloIncentivesControllerCL cl = clDeployer.createIncentivesControllerCL(VAULT, MARKET);

        assertEq(address(cl.VAULT_INCENTIVES_CONTROLLER()), VAULT_INCENTIVES_CONTROLLER);
        assertEq(address(cl.SILO_INCENTIVES_CONTROLLER()), MARKET_INCENTIVES_CONTROLLER);
    }

    function test_createIncentivesControllerCL_reverts() public {
        vm.expectRevert();
        clDeployer.createIncentivesControllerCL(address(0), MARKET);

        vm.expectRevert();
        clDeployer.createIncentivesControllerCL(VAULT, address(0));

        vm.expectRevert();
        clDeployer.createIncentivesControllerCL(MARKET, VAULT);

        vm.expectRevert(ISiloIncentivesControllerCLDeployer.UnderlyingMarketDoesNotHaveIncentives.selector);
        clDeployer.createIncentivesControllerCL(VAULT, MARKET_WITHOUT_INCENTIVES);

        vm.prank(Ownable(VAULT_INCENTIVES_MODULE).owner());
        IVaultIncentivesModule(VAULT_INCENTIVES_MODULE).addNotificationReceiver(INotificationReceiver(address(1)));
        vm.expectRevert(ISiloIncentivesControllerCLDeployer.MoreThanOneSiloVaultNotificationReceiver.selector);
        clDeployer.createIncentivesControllerCL(VAULT, MARKET);
    }

    function test_createIncentivesControllerCL_canBeAccepted() public {
        SiloIncentivesControllerCL cl = clDeployer.createIncentivesControllerCL(VAULT, MARKET);
        vm.prank(Ownable(VAULT_INCENTIVES_MODULE).owner());

        IVaultIncentivesModule(VAULT_INCENTIVES_MODULE).submitIncentivesClaimingLogic(IERC4626(MARKET), cl);
        IVaultIncentivesModule(VAULT_INCENTIVES_MODULE).acceptIncentivesClaimingLogic(IERC4626(MARKET), cl);

        address asset = address(IERC4626(MARKET).asset());
        uint256 depositAmount = 10**18;
        deal(asset, address(this), depositAmount);

        IERC20(asset).approve(MARKET, type(uint256).max);
        IERC4626(MARKET).deposit(depositAmount, address(this));
        assertTrue(IERC4626(MARKET).balanceOf(address(this)) > 0, "CL added successfully and don't revert on action");

        IERC4626(MARKET).withdraw(depositAmount / 2, address(this), address(this));
    }
}
