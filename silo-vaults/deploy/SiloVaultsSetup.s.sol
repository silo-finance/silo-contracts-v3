// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";
import {ISiloVaultDeployer} from "silo-vaults/contracts/interfaces/ISiloVaultDeployer.sol";
import {IIncentivesClaimingLogicFactory} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogicFactory.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloIncentivesController} from "silo-vaults/contracts/interfaces/ISiloIncentivesControllerCLDeployer.sol";
import {CommonDeploy} from "./common/CommonDeploy.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin5/interfaces/IERC20.sol";
import {
    ISiloIncentivesControllerCLDeployer
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCLDeployer.sol";
import {
    SiloIncentivesControllerCL
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCL.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {SiloVaultsContracts, SiloVaultsDeployments} from "silo-vaults/common/SiloVaultsContracts.sol";

/*
FOUNDRY_PROFILE=vaults ASSET=USDC SILO=0x78445e53151b523F64d70C929ED602B8F75014c8 \
    forge script silo-vaults/deploy/SiloVaultsSetup.s.sol:SiloVaultsSetup \
    --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify

This script sets up the vault for QA.

*/
contract SiloVaultsSetup is CommonDeploy, StdCheats {
    function run() public {
        AddrLib.init();

        ISiloVaultDeployer vaultDeployer = ISiloVaultDeployer(
            SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER, ChainsLib.chainAlias())
        );

        address asset = AddrLib.getAddress(vm.envString("ASSET"));
        string memory assetSymbol = IERC20Metadata(asset).symbol();
        string memory vaultName = string.concat("Silo Vault for ", assetSymbol);
        string memory vaultSymbol = string.concat("SV-", assetSymbol);

        IIncentivesClaimingLogicFactory[] memory trustedFactories = new IIncentivesClaimingLogicFactory[](1);

        trustedFactories[0] = IIncentivesClaimingLogicFactory(
            SiloVaultsDeployments.get(
                SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY, ChainsLib.chainAlias()
            )
        );

        console2.log("Trusted factories", address(trustedFactories[0]));

        ISilo[] memory silosWithIncentives = new ISilo[](0);

        uint256 privateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(privateKey);

        IERC4626 silo = IERC4626(vm.envAddress("SILO"));
        require(silo.asset() == asset, "Silo asset mismatch");

        vm.startBroadcast(privateKey);

        (ISiloVault vault, ISiloIncentivesController incentivesController, IERC4626 idleVault) = vaultDeployer.createSiloVault(
            ISiloVaultDeployer.CreateSiloVaultParams({
                initialOwner: deployer,
                initialTimelock: 0,
                asset: asset,
                incentivesControllerOwner: deployer,
                name: vaultName,
                symbol: vaultSymbol,
                trustedFactories: trustedFactories,
                silosWithIncentives: silosWithIncentives
            })
        );

        vm.stopBroadcast();

        // ISiloVault vault = ISiloVault(0x980AdDAEC01E69E55d62bA105C6045D92B323745);
        // IERC4626 idleVault = IERC4626(0x8520865cdBAA712Ba74703a82d427e08c54422Da);

        console2.log("Vault deployed at", address(vault));
        console2.log("Incentives controller deployed at", address(incentivesController));
        console2.log("Idle vault deployed at", address(idleVault));

        {
            uint256 decimals = IERC20Metadata(asset).decimals();
            uint256 supplyCap = 100 * 10 ** decimals;

            IERC4626[] memory supplyQueue = new IERC4626[](2);
            supplyQueue[0] = silo;
            supplyQueue[1] = idleVault;

            vm.startBroadcast(privateKey);

            vault.submitCap(silo, supplyCap);
            vault.submitCap(idleVault, 1000 * 10 ** decimals);
            vault.acceptCap(silo);
            vault.acceptCap(idleVault);

            vault.setSupplyQueue(supplyQueue);

            vm.stopBroadcast();
        }

        SiloIncentivesControllerCL logic;

        {
            ISiloIncentivesControllerCLDeployer controllerDeployer = ISiloIncentivesControllerCLDeployer(
                SiloVaultsDeployments.get(
                    SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_DEPLOYER, ChainsLib.chainAlias()
                )
            );

            IVaultIncentivesModule module = vault.INCENTIVES_MODULE();

            vm.startBroadcast(privateKey);
            logic = controllerDeployer.createIncentivesControllerCL(address(vault), address(silo));
            module.submitIncentivesClaimingLogic(silo, logic);
            module.acceptIncentivesClaimingLogic(silo, logic);
            vm.stopBroadcast();

            console2.log("Claiming logic deployed at", address(logic));
        }

        vm.label(address(vault), "Vault");
        vm.label(address(silo), "Silo");

        _qa(vault, logic);
    }

    function _qa(ISiloVault _vault, SiloIncentivesControllerCL _logic) internal {
        address asset = _vault.asset();
        address depositor = address(0x11);
        uint256 asetDecimals = IERC20Metadata(asset).decimals();

        deal(asset, depositor, uint256(10 ** asetDecimals));

        vm.startPrank(depositor);
        IERC4626(asset).approve(address(_vault), 1000 * 10 ** asetDecimals);
        uint256 shares = _vault.deposit(10 ** asetDecimals, depositor);

        console2.log("Shares deposited", shares);

        uint256 assets = _vault.redeem(shares, depositor, depositor);
        console2.log("Assets redeemed", assets);

        console2.log("QA Claiming logic");

        ISiloIncentivesController siloIncentives = _logic.SILO_INCENTIVES_CONTROLLER();
        ISiloIncentivesController vaultIncentives = _logic.VAULT_INCENTIVES_CONTROLLER();

        shares = _vault.deposit(IERC20(asset).balanceOf(depositor), depositor);

        uint256 amount = 10 ** asetDecimals;
        deal(asset, address(siloIncentives), amount);
        vm.stopPrank();

        vm.prank(siloIncentives.NOTIFIER());
        siloIncentives.immediateDistribution(asset, amount);

        vm.startPrank(depositor);
        assets = _vault.redeem(shares, depositor, depositor);

        console2.log("balance before claiming", IERC20(asset).balanceOf(depositor));
        vaultIncentives.claimRewards(depositor);
        console2.log("balance after claiming", IERC20(asset).balanceOf(depositor));
        require(IERC20(asset).balanceOf(depositor) > assets, "expect rewards");

        vm.stopPrank();
    }
}
