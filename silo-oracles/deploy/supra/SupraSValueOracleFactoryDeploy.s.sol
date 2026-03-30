// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {SupraSValueOracleFactory} from "silo-oracles/contracts/supra/SupraSValueOracleFactory.sol";
import {ISupraSValueOracleFactory} from "silo-oracles/contracts/interfaces/ISupraSValueOracleFactory.sol";

contract SupraSValueOracleFactoryDeploy is CommonDeploy {
    function run() public returns (ISupraSValueOracleFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        factory = ISupraSValueOracleFactory(address(new SupraSValueOracleFactory()));

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloOraclesFactoriesContracts.SUPRA_SVALUE_ORACLE_FACTORY);
    }
}
