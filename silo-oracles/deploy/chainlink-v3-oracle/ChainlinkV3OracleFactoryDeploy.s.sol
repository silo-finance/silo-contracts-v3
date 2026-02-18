// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IUniswapV3Factory} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {ChainlinkV3OracleFactory} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3OracleFactory.sol";

/*
FOUNDRY_PROFILE=oracles \
    forge script silo-oracles/deploy/chainlink-v3-oracle/ChainlinkV3OracleFactoryDeploy.s.sol \
    --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify

Resume verification:
FOUNDRY_PROFILE=oracles \
    forge script silo-oracles/deploy/chainlink-v3-oracle/ChainlinkV3OracleFactoryDeploy.s.sol \
    --ffi --rpc-url $RPC_INJECTIVE \
    --verify \
    --verifier blockscout \
    --verifier-url $VERIFIER_URL_INJECTIVE \
    --private-key $PRIVATE_KEY \
    --resume

FOUNDRY_PROFILE=oracles forge verify-contract <contract-address> \
    ChainlinkV3OracleFactory \
    --compiler-version 0.8.28 \
    --rpc-url $RPC_SONIC \
    --watch
 */
contract ChainlinkV3OracleFactoryDeploy is CommonDeploy {
    function run() public returns (ChainlinkV3OracleFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        factory = new ChainlinkV3OracleFactory();

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloOraclesFactoriesContracts.CHAINLINK_V3_ORACLE_FACTORY);
    }
}
