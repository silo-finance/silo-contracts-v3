// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {ISiloVaultDeployer} from "silo-vaults/contracts/interfaces/ISiloVaultDeployer.sol";
import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";
import {SiloVaultsDeployerDeploy} from "silo-vaults/deploy/SiloVaultsDeployerDeploy.s.sol";
import {SiloIncentivesControllerFactoryDeploy} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {SiloIncentivesControllerCLFactoryDeploy} from "silo-vaults/deploy/SiloIncentivesControllerCLFactoryDeploy.s.sol";
import {SiloVaultsFactoryDeploy} from "silo-vaults/deploy/SiloVaultsFactoryDeploy.s.sol";
import {IdleVaultsFactoryDeploy} from "silo-vaults/deploy/IdleVaultsFactoryDeploy.s.sol";
import {IdleVault} from "silo-vaults/contracts/IdleVault.sol";
import {IIncentivesClaimingLogicFactory} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogicFactory.sol";

/*
FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc SiloVaultDeployerTest -vv
*/
contract SiloVaultDeployerTest is IntegrationTest {
    using SafeERC20 for IERC20;
    uint256 constant internal _BLOCK_TO_FORK = 20329560;
    address constant internal _USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address constant internal _WS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address constant internal _USDC_WHALE = 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6;

    ISiloVaultDeployer internal _deployer;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), _BLOCK_TO_FORK);

        SiloIncentivesControllerFactoryDeploy factoryDeploy = new SiloIncentivesControllerFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();
        factoryDeploy.run();

        IdleVaultsFactoryDeploy idleVaultsFactoryDeploy = new IdleVaultsFactoryDeploy();
        idleVaultsFactoryDeploy.run();

        SiloIncentivesControllerCLFactoryDeploy clFactoryDeploy = new SiloIncentivesControllerCLFactoryDeploy();
        clFactoryDeploy.run();

        SiloVaultsFactoryDeploy vaultsFactoryDeploy = new SiloVaultsFactoryDeploy();
        vaultsFactoryDeploy.run();

        SiloVaultsDeployerDeploy deployerDeploy = new SiloVaultsDeployerDeploy();
        _deployer = deployerDeploy.run();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_SiloVaultDeployer_createSiloVault_withIdleVault -vv
    */
    function test_SiloVaultDeployer_createSiloVault_withIdleVault() public {
        ISiloVault vault;
        IERC4626 idleVault;

        (vault,, idleVault) = _deployer.createSiloVault(_params());

        assertEq(IdleVault(address(idleVault)).ONLY_DEPOSITOR(), address(vault));
        assertEq(IdleVault(address(idleVault)).asset(), vault.asset());
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_SiloVaultDeployer_createSiloVault_withIncentivesInit -vv
    */
    function test_SiloVaultDeployer_createSiloVault_withIncentivesInit() public {
        ISiloVaultDeployer.CreateSiloVaultParams memory params = _params();

        ISiloVault vault;
        ISiloIncentivesController incentivesController;

        (vault, incentivesController,) = _deployer.createSiloVault(params);

        IVaultIncentivesModule incentivesModule = vault.INCENTIVES_MODULE();

        address[] memory notificationReceivers = incentivesModule.getNotificationReceivers();

        assertEq(notificationReceivers.length, 1, "Notification receiver is not initialized");
        assertEq(notificationReceivers[0], address(incentivesController), "Notification receiver is not the incentives controller");

        address[] memory claimingLogics = incentivesModule.getMarketIncentivesClaimingLogics(
            IERC4626(address(params.silosWithIncentives[0]))
        );

        assertEq(claimingLogics.length, 1, "Claiming logic for the first market is not initialized");
        assertNotEq(claimingLogics[0], address(0), "Claiming logic for the first market is empty address");

        claimingLogics = incentivesModule.getMarketIncentivesClaimingLogics(
            IERC4626(address(params.silosWithIncentives[1]))
        );

        assertEq(claimingLogics.length, 1, "Claiming logic for the second market is not initialized");
        assertNotEq(claimingLogics[0], address(0), "Claiming logic for the second market is empty address");

        address[] memory markets = incentivesModule.getConfiguredMarkets();
        assertEq(markets.length, 2, "Markets are not initialized");
        assertEq(markets[0], address(params.silosWithIncentives[0]), "First market is not initialized");
        assertEq(markets[1], address(params.silosWithIncentives[1]), "Second market is not initialized");

        address[] memory allClaimingLogics = incentivesModule.getAllIncentivesClaimingLogics();
        assertEq(allClaimingLogics.length, 2, "All claiming logics are not initialized");
        assertNotEq(allClaimingLogics[0], address(0), "First claiming logic is empty address");
        assertNotEq(allClaimingLogics[1], address(0), "Second claiming logic is empty address");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_SiloVaultDeployer_createSiloVault_withTrustedFactories -vv
    */
    function test_SiloVaultDeployer_createSiloVault_withTrustedFactories() public {
        ISiloVaultDeployer.CreateSiloVaultParams memory params = _params();

        ISiloVault vault;

        (vault,,) = _deployer.createSiloVault(params);

        IVaultIncentivesModule incentivesModule = vault.INCENTIVES_MODULE();

        address[] memory trustedFactories = incentivesModule.getTrustedFactories();
        assertEq(trustedFactories.length, 1, "Trusted factories are not initialized");
        assertEq(trustedFactories[0], address(params.trustedFactories[0]), "Trusted factory is not initialized");
     }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_SiloVaultDeployer_createSiloVault_integration -vv
    */
    function test_SiloVaultDeployer_createSiloVault_integration() public {
        ISiloVaultDeployer.CreateSiloVaultParams memory params = _params();

        ISiloVault vault;
        ISiloIncentivesController incentivesController;

        (vault, incentivesController,) = _deployer.createSiloVault(params);

        IERC4626 market = IERC4626(address(params.silosWithIncentives[1]));
        uint256 supplyCap = type(uint128).max;

        vm.prank(params.initialOwner);
        vault.submitCap(market, supplyCap);

        vm.warp(block.timestamp + vault.timelock());

        vault.acceptCap(market);

        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = market;

        vm.prank(params.initialOwner);
        vault.setSupplyQueue(supplyQueue);

        address depositor = makeAddr("depositor");
        uint256 amount = 10_000e6;

        vm.prank(_USDC_WHALE);
        IERC20(_USDC).safeTransfer(depositor, amount);

        vm.prank(depositor);
        IERC20(_USDC).approve(address(vault), type(uint256).max);

        vm.prank(depositor);
        vault.deposit(amount, depositor);

        vm.warp(block.timestamp + 100 days);

        vault.claimRewards();

        assertEq(IERC20(_WS).balanceOf(depositor), 0, "Expect have no tokens");

        vm.prank(depositor);
        incentivesController.claimRewards(depositor);

        assertNotEq(IERC20(_WS).balanceOf(depositor), 0, "Expect to receive rewards");
    }

    function _params() internal returns (ISiloVaultDeployer.CreateSiloVaultParams memory params) {
        address initialOwner = makeAddr("initialOwner");
        address incentivesControllerOwner = makeAddr("incentivesControllerOwner");
        uint256 initialTimelock = 1 weeks;
        string memory name = "name";
        string memory symbol = "symbol";

        ISilo[] memory silosWithIncentives = new ISilo[](2);
        silosWithIncentives[0] = ISilo(0x4E216C15697C1392fE59e1014B009505E05810Df); // S/USDC(8) market USDC silo
        silosWithIncentives[1] = ISilo(0x322e1d5384aa4ED66AeCa770B95686271de61dc3); // S/USDC(20) market USDC silo

        address trustedFactory = makeAddr("trustedFactory");
        IIncentivesClaimingLogicFactory[] memory trustedFactories = new IIncentivesClaimingLogicFactory[](1);
        trustedFactories[0] = IIncentivesClaimingLogicFactory(trustedFactory);

        params = ISiloVaultDeployer.CreateSiloVaultParams({
            initialOwner: initialOwner,
            initialTimelock: initialTimelock,
            incentivesControllerOwner: incentivesControllerOwner,
            asset: _USDC,
            name: name,
            symbol: symbol,
            trustedFactories: trustedFactories,
            silosWithIncentives: silosWithIncentives
        });
    }
}
