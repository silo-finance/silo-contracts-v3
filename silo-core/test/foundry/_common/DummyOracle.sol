// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

contract DummyOracle is ISiloOracle {
    error ZeroQuote();
    
    uint256 public price;
    address public quoteToken;

    bool _expectBeforeQuote;
    bool _oracleBroken;

    constructor(uint256 _price, address _quoteToken) {
        price = _price;
        quoteToken = _quoteToken;
    }

    function beforeQuote(address _baseToken) external view {
        if (_baseToken == quoteToken) revert("beforeQuote: wrong base token");
        if (_oracleBroken) revert("beforeQuote: oracle is broken");
        if (!_expectBeforeQuote) revert("beforeQuote: was not expected, but was called anyway");
    }

    function setExpectBeforeQuote(bool _expect) external {
        _expectBeforeQuote = _expect;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function quote(uint256 _baseAmount, address _baseToken) external view returns (uint256 quoteAmount) {
        if (_baseToken == quoteToken) revert("quote: wrong base token");
        if (_oracleBroken) revert("quote: oracle is broken");

        quoteAmount = _baseAmount * price / 1e18;

        if (quoteAmount == 0) revert ZeroQuote();
    }

    function breakOracle() external {
        _oracleBroken = true;
    }

    function fixOracle() external {
        _oracleBroken = false;
    }
}
