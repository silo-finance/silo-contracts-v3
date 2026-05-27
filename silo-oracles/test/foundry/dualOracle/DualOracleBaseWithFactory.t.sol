// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";

import {DualOracleBase} from "silo-oracles/test/foundry/dualOracle/DualOracleBase.sol";
import {MockOracleFactory} from "./common/MockOracleFactory.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc DualOracleBaseWithFactoryTest
*/
contract DualOracleBaseWithFactoryTest is DualOracleBase {
    function _createDualOracle() internal override returns (IDualOracle dualOracle) {
        MockOracleFactory mockFactory = new MockOracleFactory();
        bytes memory initData = abi.encodeWithSelector(MockOracleFactory.create.selector, address(oracleMock));

        dualOracle = factory.create(
            address(mockFactory), initData, owner, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
    }
}
