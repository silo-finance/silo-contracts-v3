// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";

import {AaveFlashloan} from "silo-core/contracts/utils/flashloan/AaveFlashloan.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/interfaces/IPoolAddressesProvider.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

/*
    FOUNDRY_PROFILE=core forge clean
    FOUNDRY_PROFILE=core forge build --force

    XDC chain deployment use --legacy flag

    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/AaveFlashloanDeploy.s.sol \
        --ffi --rpc-url $RPC_SONIC --broadcast --verify --legacy
*/
contract AaveFlashloanDeploy is CommonDeploy {
    function run() public returns (AaveFlashloan aaveFlashloan) {
        string memory chainAlias = ChainsLib.chainAlias();
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        emit log_named_string("[AaveFlashloanDeploy] chainAlias", chainAlias);

        address aavePoolAddressesProvider = AddrLib.getAddress(chainAlias, AddrKey.AAVE_POOL_ADDRESSES_PROVIDER);
        require(
            aavePoolAddressesProvider != address(0),
            string.concat(AddrKey.AAVE_POOL_ADDRESSES_PROVIDER, " not deployed")
        );

        emit log_named_string("aavePoolAddressesProvider", aavePoolAddressesProvider);

        vm.startBroadcast(deployerPrivateKey);
        aaveFlashloan = new AaveFlashloan(IPoolAddressesProvider(aavePoolAddressesProvider));
        vm.stopBroadcast();

        emit log_named_string("New AaveFlashloan deployed", address(aaveFlashloan));

        _registerDeployment(address(aaveFlashloan), SiloCoreContracts.AAVE_FLASHLOAN);
    }
}
