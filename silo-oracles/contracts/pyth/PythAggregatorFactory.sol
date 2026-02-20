// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {IPythAggregatorFactory} from "silo-oracles/contracts/interfaces/IPythAggregatorFactory.sol";
import {PythAggregatorV3} from "pyth-sdk-solidity/PythAggregatorV3.sol";

/// @notice PythAggregatorFactory is a factory to deploy PythAggregatorV3 contracts. Function for the deployment is
/// permissionless. Duplicates of aggregators are not allowed. 
contract PythAggregatorFactory is Create2Factory, IPythAggregatorFactory {
    /// @inheritdoc IPythAggregatorFactory
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable override pyth;

    /// @inheritdoc IPythAggregatorFactory
    mapping (bytes32 priceId => AggregatorV3Interface aggregator) public override aggregators;

    constructor(address _pyth) {
        pyth = _pyth;
    }

    /// @inheritdoc IPythAggregatorFactory
    function deploy(
        bytes32 _priceId,
        bytes32 _externalSalt
    ) external virtual override returns (AggregatorV3Interface newAggregator) {
        if (address(aggregators[_priceId]) != address(0)) {
            revert AggregatorAlreadyExists();
        }

        newAggregator = AggregatorV3Interface(
            address(new PythAggregatorV3{salt: _salt(_externalSalt)}(pyth, _priceId))
        );

        aggregators[_priceId] = newAggregator;
        emit AggregatorDeployed(_priceId, newAggregator);
    }
}
