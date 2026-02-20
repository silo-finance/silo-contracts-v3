// SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {OracleFactory} from "../../../contracts/_common/OracleFactory.sol";

contract OracleFactoryImpl is OracleFactory {
    constructor() OracleFactory(address(1)) {}

    function saveOracle(address _newOracle, address _newConfig, bytes32 _id) external virtual {
        _saveOracle(_newOracle, _newConfig, _id);
    }
}

/*
    FOUNDRY_PROFILE=silo-oracles forge test -vv --match-contract OracleFactoryTest
*/
contract OracleFactoryTest is Test {
    OracleFactoryImpl public immutable ORACLE_FACTORY;

    constructor() {
        ORACLE_FACTORY = new OracleFactoryImpl();
    }

    /*
        FOUNDRY_PROFILE=silo-oracles forge test -vvv --match-test test_OracleFactory__saveOracle
    */
    function test_OracleFactory__saveOracle() public {
        address newOracle = address(123);
        address newConfig = address(456);
        bytes32 id = bytes32(uint256(0xa));

        ORACLE_FACTORY.saveOracle(newOracle, newConfig, id);

        assertEq(ORACLE_FACTORY.getConfigAddress(id), newConfig, "expect id => config");
        assertEq(ORACLE_FACTORY.getOracleAddress(newConfig), newOracle, "expect config => oracle");
    }
}
