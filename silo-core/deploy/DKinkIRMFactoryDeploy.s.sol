// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {
    DynamicKinkModelFactory,
    IDynamicKinkModelFactory
} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";

import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/DKinkIRMFactoryDeploy.s.sol:DKinkIRMFactoryDeploy \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/DKinkIRMFactoryDeploy.s.sol:DKinkIRMFactoryDeploy \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume

    FOUNDRY_PROFILE=core forge verify-contract 0x80e3f3d136f4B3b8A1f0693d3290184445cdee8E \
         silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol:DynamicKinkModelFactory \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch
 */
contract DKinkIRMFactoryDeploy is CommonDeploy {
    function run() public returns (IDynamicKinkModelFactory irmFactory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        irmFactory = IDynamicKinkModelFactory(address(new DynamicKinkModelFactory(new DynamicKinkModel())));

        vm.stopBroadcast();

        _registerDeployment(address(irmFactory), SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY);
    }
}
