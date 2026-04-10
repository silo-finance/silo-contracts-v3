// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;

import {CommonDeploy} from "./CommonDeploy.sol";
import {RevertingOracle} from "silo-oracles/contracts/reverting/RevertingOracle.sol";
import {SiloOraclesContracts} from "./SiloOraclesContracts.sol";

/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/RevertingOracleDeploy.s.sol \
        --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/RevertingOracleDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract RevertingOracleDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        address revertingOracle = address(new RevertingOracle());

        vm.stopBroadcast();

        _registerDeployment(revertingOracle, SiloOraclesContracts.REVERTING_ORACLE);
    }
}
