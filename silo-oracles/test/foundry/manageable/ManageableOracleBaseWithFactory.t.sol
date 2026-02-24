// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";

import {ManageableOracleBase} from "silo-oracles/test/foundry/manageable/ManageableOracleBase.sol";
import {MockOracleFactory} from "./common/MockOracleFactory.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc ManageableOracleBaseWithFactoryTest
*/
contract ManageableOracleBaseWithFactoryTest is ManageableOracleBase {
    function _createManageableOracle() internal override returns (IManageableOracle manageableOracle) {
        (address mockFactory, bytes memory initData) = _mockOracleFactoryAndInitData(address(oracleMock));

        manageableOracle = factory.create(mockFactory, initData, owner, TIMELOCK, bytes32(0));
    }

    function _mockOracleFactoryAndInitData(address _oracle)
        internal
        returns (address _mockFactory, bytes memory _initData)
    {
        _mockFactory = address(new MockOracleFactory());
        _initData = abi.encodeWithSelector(MockOracleFactory.create.selector, _oracle);
    }
}
