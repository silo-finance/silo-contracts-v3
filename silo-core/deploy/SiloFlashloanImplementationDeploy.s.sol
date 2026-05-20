// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";

import {SiloFlashloan} from "silo-core/contracts/utils/siloFlashloan/SiloFlashloan.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/interfaces/IPoolAddressesProvider.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

/*
    FOUNDRY_PROFILE=core forge clean
    FOUNDRY_PROFILE=core forge build --force 

    XDC chain deployment use --legacy flag

    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloFlashloanImplementationDeploy.s.sol \
        --ffi --rpc-url $RPC_SONIC --broadcast --verify --legacy


    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloFlashloanImplementationDeploy.s.sol \
        --verifier-url $VERIFIER_URL_ETHERSCAN_V2 \
        --verifier etherscan \
        --chain 50 \
        --ffi --rpc-url $RPC_XDC \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --verify \
        --private-key $PRIVATE_KEY \
        --legacy \
        --resume
*/
contract SiloFlashloanImplementationDeploy is CommonDeploy {
    function run() public {
        string memory chainAlias = ChainsLib.chainAlias();
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        console2.log("[SiloFlashloanImplementationDeploy] chainAlias", chainAlias);

        address siloFactory = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, chainAlias);

        require(siloFactory != address(0), string.concat(SiloCoreContracts.SILO_FACTORY, " not deployed"));
        console2.log("siloFactory", siloFactory);

        console2.log("\n[SiloFlashloanImplementationDeploy] deploying new Silo\n");

        address aavePoolAddressesProvider = AddrLib.getAddress(chainAlias, AddrKey.AAVE_POOL_ADDRESSES_PROVIDER);
        require(aavePoolAddressesProvider != address(0), string.concat(AddrKey.AAVE_POOL_ADDRESSES_PROVIDER, " not deployed"));
        console2.log("aavePoolAddressesProvider", aavePoolAddressesProvider);

        vm.startBroadcast(deployerPrivateKey);
        address siloImpl = address(new SiloFlashloan(ISiloFactory(siloFactory), IPoolAddressesProvider(aavePoolAddressesProvider)));
        vm.stopBroadcast();
        
        console2.log("New SiloImplementation deployed", siloImpl);

        _registerDeployment(siloImpl, SiloCoreContracts.SILO_FLASHLOAN);
    }
}
