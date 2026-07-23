// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {
    DualOracleISiloOracleTestBase
} from "silo-oracles/test/foundry/dualOracle/DualOracleISiloOracleTestBase.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc DualOracleISiloOracleWithOracleTest
*/
contract DualOracleISiloOracleWithOracleTest is DualOracleISiloOracleTestBase {
    uint256 private constant LOWER_BOUND = 0.5e18;
    uint256 private constant UPPER_BOUND = 2e18;

    function _createDualOracle() internal override returns (ISiloOracle) {
        return ISiloOracle(address(
            factory.create(ISiloOracle(address(oracleMock)), owner, address(0), TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0))
        ));
    }
}
