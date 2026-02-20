// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {SiloOraclesFactoriesContracts} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {ManageableOracleDeploy} from "silo-oracles/deploy/manageable/ManageableOracleDeploy.s.sol";
import {
    ManageableOracleISiloOracleTestBase
} from "silo-oracles/test/foundry/manageable/ManageableOracleISiloOracleTestBase.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc ManageableOracleISiloOracleWithOracleTest
*/
contract ManageableOracleISiloOracleWithOracleTest is ManageableOracleISiloOracleTestBase {
    function _createManageableOracle() internal override returns (ISiloOracle manageableOracle) {
        ManageableOracleDeploy oracleDeployer = new ManageableOracleDeploy();
        oracleDeployer.disableDeploymentsSync();

        console2.log("address(factory)", address(factory));

        AddrLib.init();
        AddrLib.setAddress(SiloOraclesFactoriesContracts.MANAGEABLE_ORACLE_FACTORY, address(factory));
        vm.setEnv("BASE_TOKEN", "BASE_TOKEN_FOR_TEST");
        AddrLib.setAddress("BASE_TOKEN_FOR_TEST", baseToken);

        vm.setEnv("OWNER", "OWNER_FOR_TEST");
        AddrLib.setAddress("OWNER_FOR_TEST", owner);

        vm.setEnv("TIMELOCK", vm.toString(timelock));
        vm.setEnv("EXTERNAL_SALT", vm.toString(bytes32(0)));

        vm.setEnv("UNDERLYING_ORACLE", "UNDERLYING_ORACLE_FOR_TEST");
        AddrLib.setAddress("UNDERLYING_ORACLE_FOR_TEST", address(oracleMock));

        vm.mockCall(
            address(oracleMock.quoteToken()),
            abi.encodeWithSelector(IERC20Metadata.symbol.selector),
            abi.encode("TEST_QUOTE_TOKEN")
        );

        manageableOracle = ISiloOracle(address(oracleDeployer.run()));
    }
}
