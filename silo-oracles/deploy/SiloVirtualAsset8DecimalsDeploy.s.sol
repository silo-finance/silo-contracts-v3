// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;

import {CommonDeploy} from "./CommonDeploy.sol";
import {SiloVirtualAsset8Decimals} from "silo-oracles/contracts/silo-virtual-assets/SiloVirtualAsset8Decimals.sol";
import {SiloOraclesContracts} from "./SiloOraclesContracts.sol";

/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/SiloVirtualAsset8DecimalsDeploy.s.sol \
        --ffi --rpc-url $RPC_INK --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/SiloVirtualAsset8DecimalsDeploy.s.sol \
        --ffi --rpc-url $RPC_INK \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INK \
        --private-key $PRIVATE_KEY \
        --resume

    FOUNDRY_PROFILE=oracles forge verify-contract <contract-address> \
        silo-oracles/contracts/silo-virtual-assets/SiloVirtualAsset8Decimals.sol:SiloVirtualAsset8Decimals \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch

    XDC chain deployment:

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/SiloVirtualAsset8DecimalsDeploy.s.sol \
        --ffi --rpc-url $RPC_XDC --legacy --broadcast --verify

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/SiloVirtualAsset8DecimalsDeploy.s.sol \
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
contract SiloVirtualAsset8DecimalsDeploy is CommonDeploy {
    function run() public returns (address asset) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        asset = address(new SiloVirtualAsset8Decimals());

        vm.stopBroadcast();

        _registerDeployment(asset, SiloOraclesContracts.SILO_VIRTUAL_ASSET_8_DECIMALS);
    }
}
