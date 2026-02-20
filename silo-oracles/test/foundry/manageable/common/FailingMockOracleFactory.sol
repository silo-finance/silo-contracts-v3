// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

/* Mock factory that fails when called */
contract FailingMockOracleFactory {
    function create() external pure {
        revert("Factory call failed");
    }
}
