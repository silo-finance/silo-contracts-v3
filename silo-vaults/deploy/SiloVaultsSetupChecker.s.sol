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
import {IdleVault} from "silo-vaults/contracts/IdleVault.sol";
import {
    IBackwardsCompatibleGaugeLike
} from "silo-core/contracts/incentives/interfaces/IBackwardsCompatibleGaugeLike.sol";
import {
    SiloIncentivesControllerCLFactory
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCLFactory.sol";
import {
    SiloIncentivesControllerCLDeployer
} from "silo-vaults/contracts/incentives/claiming-logics/SiloIncentivesControllerCLDeployer.sol";

/*
FOUNDRY_PROFILE=vaults VAULT=0x5362D5086FDef73450145492a66F8EBF210c5B9C \
SILO=0xf82C626E99C68e7af81F4E6afC8Cd25cA13702DB \
    forge script silo-vaults/deploy/SiloVaultsSetupChecker.s.sol:SiloVaultsSetupChecker \
    --ffi --rpc-url $RPC_MAINNET --broadcast --verify


Silo Optima Ethereum Vault: https://app.silo.finance/vaults/ethereum/0x5362D5086FDef73450145492a66F8EBF210c5B9C?action=deposit

Markets:

savUSD (v3 market) https://etherscan.io/address/0x74b21d458b9d5cf59f4b4e10a2e829c221670ee3
0xf82C626E99C68e7af81F4E6afC8Cd25cA13702DB

PT-savUSD Market Config https://etherscan.io/address/0x493558e4201bde0a4b2d4c1e0234a3d88d4cdad8
0xc2B4316331303Bf31fEe9854709271851099138E

PT-reUSD Market Config https://etherscan.io/address/0x18b178b50f1ffd3dc7855c893a4e1ac618f9b76a
0x8c6564Ad2f1728a0E024dbDbFe8108680B909008

*/
contract SiloVaultsSetupChecker is CommonDeploy, StdCheats {
    function run() public {
        AddrLib.init();

        ISiloVault vault = ISiloVault(vm.envAddress("VAULT"));
        ISilo silo = ISilo(vm.envAddress("SILO"));

        console2.log("Silo", address(silo));
        console2.log("VAULT", address(vault));

        address asset = vault.asset();
        console2.log("Asset", asset, IERC20Metadata(asset).symbol());

        require(asset == silo.asset(), "Asset mismatch");

        IVaultIncentivesModule module = vault.INCENTIVES_MODULE();
        console2.log("Vault incentives module", address(module));
        address vaultOwner = vault.owner();
        console2.log("Vault owner", vaultOwner);
        address[] memory trustedFactories = module.getTrustedFactories();

        address trustedFactory = SiloVaultsDeployments.get(
            SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_FACTORY, ChainsLib.chainAlias()
        );

        console2.log("Current (deployed) trusted factory: %s\n\n", trustedFactory);
        bool found = false;

        for (uint256 i; i < trustedFactories.length; i++) {
            if (trustedFactories[i] == trustedFactory) found = true;
        }

        console2.log(found ? "Trusted factory found" : "Trusted factory NOT found, timelock will be required");

        uint256 cap = vault.config(silo).cap;
        console2.log("Silo cap =>", cap == 0 ? "0 - market NOT cofigured" : "market is set in Vault");

        address[] memory logics = module.getMarketIncentivesClaimingLogics(silo);

        if (logics.length == 0) {
            console2.log("No incentives claiming logics found for silo");
        }

        for (uint256 i; i < logics.length; i++) {
            ISiloIncentivesController sic = SiloIncentivesControllerCL(logics[i]).SILO_INCENTIVES_CONTROLLER();
            address shareToken = sic.SHARE_TOKEN();
            console2.log("Share token", shareToken, IERC20Metadata(shareToken).symbol());

            if (shareToken == address(silo)) {
                console2.log("Silo incentives controller is setup for liquidation rewards");
                return;
            }
        }

        SiloIncentivesControllerCL logic;

        {
            ISiloIncentivesControllerCLDeployer controllerDeployer = ISiloIncentivesControllerCLDeployer(
                SiloVaultsDeployments.get(
                    SiloVaultsContracts.SILO_INCENTIVES_CONTROLLER_CL_DEPLOYER, ChainsLib.chainAlias()
                )
            );

            // to test current repo code, deploy here
            // ISiloIncentivesControllerCLDeployer controllerDeployer = new SiloIncentivesControllerCLDeployer(new SiloIncentivesControllerCLFactory());

            console2.log("Claiming logic deployer", address(controllerDeployer));

            uint256 privateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
            vm.startBroadcast(privateKey);
            logic = controllerDeployer.createIncentivesControllerCL(address(vault), address(silo));
            vm.stopBroadcast();

            console2.log("Claiming logic deployed at", address(logic));
            vm.label(address(logic), "NEW LOGIC");

            vm.startPrank(vaultOwner);
            module.submitIncentivesClaimingLogic(silo, logic);
            vm.warp(block.timestamp + vault.timelock());
            module.acceptIncentivesClaimingLogic(silo, logic);
            vm.stopPrank();

            _qa(vault, silo, logic);

            vm.startPrank(vaultOwner);
            module.removeIncentivesClaimingLogic(silo, logic);
            vm.stopPrank();

            // multisig tx data:
            console2.log("create multisig tx that will submit incentives claiming logic to the vault");
        }

        vm.label(address(vault), "Vault");
        vm.label(address(silo), "Silo");
    }

    function _qa(ISiloVault _vault, ISilo _silo, SiloIncentivesControllerCL _logic) internal {
        address asset = _vault.asset();
        address depositor = address(0x11);
        uint256 asetDecimals = IERC20Metadata(asset).decimals();
        uint256 depositAmount = 1e3 * (10 ** asetDecimals);

        uint256 balanceOfVault = _silo.balanceOf(address(_vault));
        console2.log("silo balance of vault", balanceOfVault);

        if (balanceOfVault == 0) {
            _setSiloOnVault(_vault, _silo);
        }

        deal(asset, depositor, depositAmount);

        vm.startPrank(depositor);
        IERC4626(asset).approve(address(_vault), type(uint256).max);
        uint256 shares = _vault.deposit(depositAmount, depositor);

        console2.log("Shares deposited", shares);
        console2.log("    total shares", _vault.totalSupply());

        uint256 assets = _vault.redeem(shares, depositor, depositor);
        console2.log("Assets redeemed", assets);

        console2.log("\n\nQA Claiming logic\n");

        ISiloIncentivesController siloIncentives = _logic.SILO_INCENTIVES_CONTROLLER();
        ISiloIncentivesController vaultIncentives = _logic.VAULT_INCENTIVES_CONTROLLER();

        shares = _vault.deposit(IERC20(asset).balanceOf(depositor), depositor);
        console2.log("deposit to vault done", shares);

        uint256 amount = 1e3 * (10 ** asetDecimals);
        deal(asset, address(siloIncentives), amount);
        vm.stopPrank();

        console2.log("controller address", address(siloIncentives));

        try IBackwardsCompatibleGaugeLike(address(siloIncentives)).is_killed() {
            console2.log("\nsilo incentives is backwards compatible - GOOD!");
        } catch {
            revert("controller is not compatible!");
        }

        vm.prank(siloIncentives.NOTIFIER());
        siloIncentives.immediateDistribution(asset, amount);
        console2.log("immediateDistribution done");

        vm.startPrank(depositor);
        assets = _vault.redeem(shares, depositor, depositor);

        console2.log("balance before claiming", IERC20(asset).balanceOf(depositor));
        vaultIncentives.claimRewards(depositor);
        console2.log("balance after claiming", IERC20(asset).balanceOf(depositor));
        vm.stopPrank();

        // require(IERC20(asset).balanceOf(depositor) > assets, "expect rewards");
    }

    function _setSiloOnVault(ISiloVault _vault, ISilo _silo) internal {
        console2.log("setting silo on vaul for QA purposes");

        address asset = _vault.asset();
        uint256 decimals = IERC20Metadata(asset).decimals();
        uint256 supplyCap = 1e6 * 10 ** decimals;

        IdleVault idleVault = new IdleVault({onlyDepositor: address(_vault), _asset: asset, _name: "a", _symbol: "b"});

        IERC4626[] memory supplyQueue = new IERC4626[](2);
        supplyQueue[0] = _silo;
        supplyQueue[1] = idleVault;

        vm.startPrank(_vault.owner());

        _vault.submitCap(_silo, supplyCap);
        _vault.submitCap(idleVault, 1e9 * 10 ** decimals);

        vm.warp(block.timestamp + _vault.timelock());

        console2.log("accepting silo cap...");

        // _vault.acceptCap(_silo);
        _vault.acceptCap(idleVault);

        console2.log("setting supply queue...");

        _vault.setSupplyQueue(supplyQueue);

        vm.stopPrank();
    }
}
