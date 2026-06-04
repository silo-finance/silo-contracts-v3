// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

/* Mock factory for testing - returns the oracle address passed to it */
contract MockOracleFactory {
    function create(address _oracle) external pure returns (address) {
        return _oracle;
    }
}
