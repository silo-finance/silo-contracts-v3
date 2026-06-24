// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {DualOracleFactory} from "silo-oracles/contracts/dualOracle/DualOracleFactory.sol";
import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";

/*
FOUNDRY_PROFILE=oracles \
    forge script silo-oracles/deploy/dualOracle/DualOracleFactoryDeploy.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast --verify
 */
contract DualOracleFactoryDeploy is CommonDeploy {
    function run() public returns (address factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        factory = address(new DualOracleFactory());

        vm.stopBroadcast();

        _registerDeployment(factory, SiloOraclesFactoriesContracts.DUAL_ORACLE_FACTORY);
    }
}
