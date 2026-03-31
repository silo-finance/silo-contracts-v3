// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {ISupraOraclePull_V2} from "silo-oracles/contracts/interfaces/ISupraOraclePull_V2.sol";
import {SupraSValueOracleFactory} from "silo-oracles/contracts/supra/SupraSValueOracleFactory.sol";
import {ISupraSValueOracleFactory} from "silo-oracles/contracts/interfaces/ISupraSValueOracleFactory.sol";

contract SupraSValueOracleFactoryDeploy is CommonDeploy {
    ISupraOraclePull_V2 internal constant SUPRA_ORACLE_PULL =
        ISupraOraclePull_V2(0x2FA6DbFe4291136Cf272E1A3294362b6651e8517);

    function run() public returns (ISupraSValueOracleFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        factory = ISupraSValueOracleFactory(address(new SupraSValueOracleFactory(SUPRA_ORACLE_PULL)));

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloOraclesFactoriesContracts.SUPRA_SVALUE_ORACLE_FACTORY);
    }
}
