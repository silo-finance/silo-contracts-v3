// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {DualOracleBase} from "silo-oracles/test/foundry/dualOracle/DualOracleBase.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc DualOracleBaseWithOracleTest
*/
contract DualOracleBaseWithOracleTest is DualOracleBase {
    function _createDualOracle() internal override returns (IDualOracle dualOracle) {
        dualOracle = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
    }
}
