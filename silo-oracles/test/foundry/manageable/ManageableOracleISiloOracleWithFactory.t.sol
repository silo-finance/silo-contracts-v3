// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {
    ManageableOracleISiloOracleTestBase
} from "silo-oracles/test/foundry/manageable/ManageableOracleISiloOracleTestBase.sol";
import {MockOracleFactory} from "./common/MockOracleFactory.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc ManageableOracleISiloOracleWithFactoryTest
*/
contract ManageableOracleISiloOracleWithFactoryTest is ManageableOracleISiloOracleTestBase {
    function _createManageableOracle() internal override returns (ISiloOracle manageableOracle) {
        (address mockFactory, bytes memory initData) = _mockOracleFactoryAndInitData(address(oracleMock));

        manageableOracle = ISiloOracle(address(factory.create(mockFactory, initData, owner, timelock, bytes32(0))));
    }

    function _mockOracleFactoryAndInitData(address _oracle)
        internal
        returns (address _mockFactory, bytes memory _initData)
    {
        _mockFactory = address(new MockOracleFactory());
        _initData = abi.encodeWithSelector(MockOracleFactory.create.selector, _oracle);
    }
}
