// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {AddrKey} from "common/addresses/AddrKey.sol";

import {RescueVaultBalance} from "../../contracts/utils/RescueVaultBalance.sol";

import {CommonDeploy} from "../common/CommonDeploy.sol";

/*
    FOUNDRY_PROFILE=vaults MARKET=0xB77FF64638A2CaB0a102B3c7964514Cb50D577ca \
        forge script silo-vaults/deploy/utils/RescueVaultBalanceDeploy.s.sol:RescueVaultBalanceDeploy \
        --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=vaults MARKET=0xB77FF64638A2CaB0a102B3c7964514Cb50D577ca \
        forge script silo-vaults/deploy/utils/RescueVaultBalanceDeploy.s.sol:RescueVaultBalanceDeploy \
        --ffi --rpc-url $RPC_ARBITRUM \
        --verify \
        --verifier blockscout --verifier-url $ETHERSCAN_API_KEY \
        --private-key $PRIVATE_KEY \
        --resume
*/
contract RescueVaultBalanceDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        address receiver = AddrLib.getAddressSafe(ChainsLib.chainAlias(), AddrKey.GROWTH_MULTISIG);
        IERC4626 market = IERC4626(vm.envAddress("MARKET"));

        vm.startBroadcast(deployerPrivateKey);
        RescueVaultBalance newLogic = new RescueVaultBalance({_receiver: receiver, _market: market});

        vm.stopBroadcast();

        _registerDeployment(address(newLogic), "RescueVaultBalance.sol");
    }
}
