// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

interface IFlatPriceOracleFactory {
    event FlatPriceOracleCreated(ISiloOracle indexed oracle);

    function create(
        uint256 _price,
        address _baseToken,
        address _quoteToken,
        bytes32 _externalSalt
    ) external returns (ISiloOracle oracle);
}
