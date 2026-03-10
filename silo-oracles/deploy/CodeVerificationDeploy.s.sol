// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./CommonDeploy.sol";

import {
    ChainlinkV3OracleConfig,
    IChainlinkV3Oracle
} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3OracleConfig.sol";
import {SiloOraclesFactoriesContracts} from "./SiloOraclesFactoriesContracts.sol";

/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/CodeVerificationDeploy.s.sol \
        --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/CodeVerificationDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
*/
contract CodeVerificationDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory config;

        vm.startBroadcast(deployerPrivateKey);

        address chainlinkConfig = address(new ChainlinkV3OracleConfig(config));

        vm.stopBroadcast();

        _registerDeployment(chainlinkConfig, SiloOraclesFactoriesContracts.CHAINLINK_V3_ORACLE_CONFIG);
    }
}
