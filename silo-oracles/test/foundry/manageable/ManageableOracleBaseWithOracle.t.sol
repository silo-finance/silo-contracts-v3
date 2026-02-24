// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {SiloOraclesFactoriesContracts} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {Create2Factory} from "silo-oracles/contracts/_common/Create2Factory.sol";
import {ManageableOracleBase} from "silo-oracles/test/foundry/manageable/ManageableOracleBase.sol";
import {ManageableOracleDeploy} from "silo-oracles/deploy/manageable/ManageableOracleDeploy.s.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc ManageableOracleBaseWithOracleTest
*/
contract ManageableOracleBaseWithOracleTest is ManageableOracleBase, Create2Factory {
    ManageableOracleDeploy oracleDeployer;

    function _predictOracleAddress() internal view override returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        bytes32 externalSalt = bytes32(0);

        return factory.predictAddress(address(deployer), externalSalt);
    }

    function _createManageableOracle() internal override returns (IManageableOracle manageableOracle) {
        manageableOracle = oracleDeployer.run();
    }

    function _beforeOracleCreation() internal override {
        super._beforeOracleCreation();

        oracleDeployer = new ManageableOracleDeploy();
        oracleDeployer.disableDeploymentsSync();

        console2.log("address(factory)", address(factory));

        // forge-lint: disable-start(unsafe-cheatcode)

        AddrLib.init();
        AddrLib.setAddress(SiloOraclesFactoriesContracts.MANAGEABLE_ORACLE_FACTORY, address(factory));
        vm.setEnv("BASE_TOKEN", "BASE_TOKEN_FOR_TEST");
        AddrLib.setAddress("BASE_TOKEN_FOR_TEST", baseToken);

        vm.setEnv("OWNER", "OWNER_FOR_TEST");
        AddrLib.setAddress("OWNER_FOR_TEST", owner);

        vm.setEnv("TIMELOCK", vm.toString(TIMELOCK));
        vm.setEnv("EXTERNAL_SALT", vm.toString(bytes32(0)));

        vm.setEnv("UNDERLYING_ORACLE", "UNDERLYING_ORACLE_FOR_TEST");
        AddrLib.setAddress("UNDERLYING_ORACLE_FOR_TEST", address(oracleMock));

        // forge-lint: disable-end(unsafe-cheatcode)

        vm.mockCall(
            address(oracleMock.quoteToken()),
            abi.encodeWithSelector(IERC20Metadata.symbol.selector),
            abi.encode("TEST_QUOTE_TOKEN")
        );
    }
}
