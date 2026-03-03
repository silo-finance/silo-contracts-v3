// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IVaultIncentivesModule} from "silo-vaults/contracts/interfaces/IVaultIncentivesModule.sol";
import {SiloVault} from "silo-vaults/contracts/SiloVault.sol";

import {CommonDeploy} from "./common/CommonDeploy.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

/*
FOUNDRY_PROFILE=vaults ASSET=WETH \
    forge script silo-vaults/deploy/SiloVaultsDeploy.s.sol:SiloVaultsDeploy \
    --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify --slow 

Resume verification:
FOUNDRY_PROFILE=vaults \
    forge script silo-vaults/deploy/SiloVaultsDeploy.s.sol:SiloVaultsDeploy \
    --ffi --rpc-url $RPC_INJECTIVE \
    --verify \
    --verifier blockscout --verifier-url $VERIFIER_URL_INJECTIVE \
    --private-key $PRIVATE_KEY \
    --resume
*/
contract SiloVaultsDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        AddrLib.init();

        address owner = msg.sender;
        uint256 initialTimelock = 1 days;
        IVaultIncentivesModule vaultIncentivesModule = IVaultIncentivesModule(address(1));
        address asset = AddrLib.getAddress(vm.envString("ASSET"));
        string memory name = "just for code verification";
        string memory symbol = "V";


        vm.startBroadcast(deployerPrivateKey);

        new SiloVault({
            _owner: owner,
            _initialTimelock: initialTimelock,
            _vaultIncentivesModule: vaultIncentivesModule,
            _asset: asset,
            _name: name,
            _symbol: symbol
        });

        vm.stopBroadcast();
    }
}
