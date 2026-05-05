// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";
import {Create2Factory} from "common/utils/Create2Factory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {FlatPriceOracle} from "silo-oracles/contracts/flat-price/FlatPriceOracle.sol";
import {IFlatPriceOracle} from "silo-oracles/contracts/interfaces/IFlatPriceOracle.sol";
import {IFlatPriceOracleFactory} from "silo-oracles/contracts/interfaces/IFlatPriceOracleFactory.sol";

contract FlatPriceOracleFactory is Create2Factory, IFlatPriceOracleFactory {
    address public immutable ORACLE_IMPLEMENTATION; // solhint-disable-line var-name-mixedcase
    mapping(address => bool) public createdInFactory;

    constructor() {
        ORACLE_IMPLEMENTATION = address(new FlatPriceOracle());
    }

    function create(
        uint256 _price,
        address _baseToken,
        address _quoteToken,
        bytes32 _externalSalt
    ) external returns (ISiloOracle oracle) {
        oracle = ISiloOracle(
            Clones.cloneDeterministic({implementation: ORACLE_IMPLEMENTATION, salt: _salt(_externalSalt)})
        );

        IFlatPriceOracle(address(oracle)).initialize(_price, _baseToken, _quoteToken);
        createdInFactory[address(oracle)] = true;

        emit FlatPriceOracleCreated(oracle);
    }
}
