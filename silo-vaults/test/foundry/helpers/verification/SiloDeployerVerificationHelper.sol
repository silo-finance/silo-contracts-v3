// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {Vm} from "gitmodules/forge-std/src/Vm.sol";
import {console} from "gitmodules/forge-std/src/console.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {SiloVaultsContracts, SiloVaultsDeployments} from "silo-vaults/common/SiloVaultsContracts.sol";
import {ISiloVaultBase} from "silo-vaults/contracts/interfaces/ISiloVault.sol";
import {SiloIncentivesController} from "silo-core/contracts/incentives/SiloIncentivesController.sol";

/**
FOUNDRY_PROFILE=vaults \
    SILO_VAULT_DEPLOYER=<deployer_address> \
    VAULT_ADDRESS=<vault_address> \
    VAULT_CREATION_BLOCK=<block_number> \
    forge script silo-vaults/test/foundry/helpers/verification/SiloDeployerVerificationHelper.sol \
    --ffi --rpc-url $RPC_SONIC
 */
contract SiloDeployerVerificationHelper is Script {
    function run() public {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddress != address(0), "VAULT_ADDRESS is not set");

        uint256 vaultCreationBlock = vm.envUint("VAULT_CREATION_BLOCK");
        require(vaultCreationBlock != 0, "VAULT_CREATION_BLOCK is not set");

        AddrLib.init();
        string memory chainAlias = ChainsLib.chainAlias();

        address deployer = SiloVaultsDeployments.get(SiloVaultsContracts.SILO_VAULT_DEPLOYER, chainAlias);

        deployer = vm.envOr("SILO_VAULT_DEPLOYER", deployer);
        require(deployer != address(0), "SILO_VAULT_DEPLOYER is not deployed on this chain");

        bytes32[] memory topics = new bytes32[](2);
        topics[0] = keccak256("CreateSiloVault(address,address,address)");
        topics[1] = bytes32(uint256(uint160(vaultAddress)));

        Vm.EthGetLogs[] memory logs = vm.eth_getLogs({
            fromBlock: vaultCreationBlock,
            toBlock: vaultCreationBlock,
            target: deployer,
            topics: topics
        });

        require(logs.length == 1, "No logs found");

        address asset = IERC4626(vaultAddress).asset();

        (address incentivesController, address idleVault) = abi.decode(logs[0].data, (address, address));

        _printIdleVaultData(idleVault, vaultAddress, asset);
        _printIncentivesControllerData(incentivesController, vaultAddress);
        _printVaultData(vaultAddress);
    }

    function _printIdleVaultData(address _idleVault, address _vault, address _asset) internal view {
        require(_idleVault != address(0), "Idle vault is not deployed");

        string memory idleVaultName = IERC4626(_idleVault).name();
        string memory idleVaultSymbol = IERC4626(_idleVault).symbol();

        console.log("\nIdleVault details:");
        console.log("IdleVault:", _idleVault);
        console.log("Name:", idleVaultName);
        console.log("Symbol:", idleVaultSymbol);
        console.log("Vault:", _vault);
        console.log("Asset:", _asset);

        // constructor args: address vault, address asset, string name, string symbol
        bytes memory constructorArgs = abi.encode(_vault, _asset, idleVaultName, idleVaultSymbol);

        console.log("constructorArgs:", vm.toString(constructorArgs));
    }

    function _printIncentivesControllerData(address _incentivesController, address _vault) internal view {
        address owner = Ownable(_incentivesController).owner();
        address notifier = SiloIncentivesController(_incentivesController).NOTIFIER();
    
        console.log("\nIncentivesController details:");
        console.log("IncentivesController:", _incentivesController);
        console.log("Owner:", owner);
        console.log("Notifier:", notifier);
        console.log("Vault (should be notifier):", _vault);

        // constructor args: address owner, address notifier
        bytes memory constructorArgs = abi.encode(owner, notifier);

        console.log("constructorArgs:", vm.toString(constructorArgs));
    }

    function _printVaultData(address _vault) internal view {
        address asset = IERC4626(_vault).asset();
        address owner = Ownable(_vault).owner();
        address incentivesModule = address(ISiloVaultBase(_vault).INCENTIVES_MODULE());
        uint256 timelock = ISiloVaultBase(_vault).timelock();
        string memory name = IERC4626(_vault).name();
        string memory symbol = IERC4626(_vault).symbol();

        console.log("\nVault details:");
        console.log("Vault:", _vault);
        console.log("initial owner:", owner);
        console.log("initial timelock:", timelock);
        console.log("Asset:", asset);
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Incentives module:", incentivesModule);

        // constructor args:
        //  address initialOwner,
        //  uint256 initialTimelock,
        //  address vaultIncentivesModule,
        //  address asset,
        //  string name,
        //  string symbol

        bytes memory constructorArgs = abi.encode(owner, timelock, incentivesModule, asset, name, symbol);

        console.log("constructorArgs:", vm.toString(constructorArgs));
    }
}
