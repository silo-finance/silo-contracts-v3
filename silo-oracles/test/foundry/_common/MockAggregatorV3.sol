// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

/// @dev MockAggregatorV3 is AggregatorV3Interface for QA purposes only, must never be deployed.
contract MockAggregatorV3 is AggregatorV3Interface {
    int256 public immutable MOCKED_ANSWER;
    uint8 public immutable MOCKED_DECIMALS;

    constructor(int256 _answer, uint8 _decimals) {
        MOCKED_ANSWER = _answer;
        MOCKED_DECIMALS = _decimals;
    }

    function decimals() external view virtual override returns (uint8) {
        return MOCKED_DECIMALS;
    }

    function description() external view virtual override returns (string memory) {
        return "Mocked aggregator for QA only";
    }

    function version() external view virtual override returns (uint256) {
        return 12345;
    }

    function getRoundData(uint80)
        external
        view
        virtual
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 54321;
        answer = MOCKED_ANSWER;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 123;
    }

    function latestRoundData()
        external
        view
        virtual
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 54321;
        answer = MOCKED_ANSWER;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 1234;
    }
}
