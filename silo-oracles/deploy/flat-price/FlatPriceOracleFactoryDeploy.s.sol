// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {FlatPriceOracleFactory} from "silo-oracles/contracts/flat-price/FlatPriceOracleFactory.sol";
import {IFlatPriceOracleFactory} from "silo-oracles/contracts/interfaces/IFlatPriceOracleFactory.sol";

/*
FOUNDRY_PROFILE=oracles \
    forge script silo-oracles/deploy/flat-price/FlatPriceOracleFactoryDeploy.s.sol \
    --ffi --rpc-url $RPC_ARBITRUM --broadcast --verify
*/
contract FlatPriceOracleFactoryDeploy is CommonDeploy {
    function run() public returns (IFlatPriceOracleFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        factory = IFlatPriceOracleFactory(address(new FlatPriceOracleFactory()));

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloOraclesFactoriesContracts.FLAT_PRICE_ORACLE_FACTORY);
    }
}
