// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IVersioned {
    /// @notice Returns the version of the contract
    /// @return version The version of the contract in format "SiloLens v3.17.0"
    function VERSION() external pure returns (string memory version); // solhint-disable-line func-name-mixedcase
}
