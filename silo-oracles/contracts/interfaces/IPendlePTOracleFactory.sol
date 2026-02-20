// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

interface IPendlePTOracleFactory {
    event PendlePTOracleCreated(ISiloOracle indexed pendlePTOracle);

    /// @notice Create a new PendlePTOracle
    /// @param _underlyingOracle Oracle for PT token's underlying asset.
    /// @param _market Pendle market's address.
    /// @param _externalSalt The external salt to be used together with factory salt
    /// @return pendlePTOracle The pendlePTOracle created.
    function create(
        ISiloOracle _underlyingOracle,
        address _market,
        bytes32 _externalSalt
    ) external returns (ISiloOracle pendlePTOracle);
}
