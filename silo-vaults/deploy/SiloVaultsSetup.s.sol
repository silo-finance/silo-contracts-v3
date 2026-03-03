// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";

import {CommonDeploy} from "./common/CommonDeploy.sol";
import {IERC20Metadata} from "openzeppelin5/interfaces/IERC20Metadata.sol";

/*
FOUNDRY_PROFILE=vaults VAULT=0x5134dD226ba8F035224C2d393D6d5a41D006C018 \
    forge script silo-vaults/deploy/SiloVaultsSetup.s.sol:SiloVaultsSetup \
    --ffi --rpc-url $RPC_ARBITRUM --broadcast

This script sets up the vault for QA.

*/
contract SiloVaultsSetup is CommonDeploy {
    function run() public {
        ISiloVault vault = ISiloVault(vm.envAddress("VAULT"));
        uint256 supplyCap = 10 * 10 ** IERC20Metadata(vault.asset()).decimals();

        vm.startBroadcast(uint256(vm.envBytes32("PRIVATE_KEY")));

        vault.submitCap(vault, supplyCap);

        vm.stopBroadcast();
    }
}
