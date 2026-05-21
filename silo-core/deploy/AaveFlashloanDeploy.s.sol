// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
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


    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/AaveFlashloanDeploy.s.sol \
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
contract AaveFlashloanDeploy is CommonDeploy {
    function run() public returns (AaveFlashloan aaveFlashloan) {
        string memory chainAlias = ChainsLib.chainAlias();
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        console2.log("[AaveFlashloanDeploy] chainAlias", chainAlias);

        address aavePoolAddressesProvider = AddrLib.getAddress(chainAlias, AddrKey.AAVE_POOL_ADDRESSES_PROVIDER);
        require(aavePoolAddressesProvider != address(0), string.concat(AddrKey.AAVE_POOL_ADDRESSES_PROVIDER, " not deployed"));
        console2.log("aavePoolAddressesProvider", aavePoolAddressesProvider);

        vm.startBroadcast(deployerPrivateKey);
        aaveFlashloan = new AaveFlashloan(IPoolAddressesProvider(aavePoolAddressesProvider));
        vm.stopBroadcast();
        
        console2.log("New AaveFlashloan deployed", address(aaveFlashloan));

        _registerDeployment(address(aaveFlashloan), SiloCoreContracts.AAVE_FLASHLOAN);
    }
}
