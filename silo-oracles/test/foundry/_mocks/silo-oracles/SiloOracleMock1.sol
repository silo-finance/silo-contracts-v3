// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {StdCheatsSafe} from "forge-std/StdCheats.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

contract SiloOracleMock1 is StdCheatsSafe, ISiloOracle {
    uint256 public price = 1000000000000000000;
    address public tokenAsQuote = makeAddr("SiloOracleMock.quoteToken");
    address public baseToken = makeAddr("SiloOracleMock.baseToken");

    event BeforeQuoteSiloOracleMock1();

    function beforeQuote(address /* _baseToken */ ) external {
        emit BeforeQuoteSiloOracleMock1();
    }

    function setQuoteToken(address _quoteToken) external {
        tokenAsQuote = _quoteToken;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function quote(uint256, /* _baseAmount */ address /* _baseToken */ )
        external
        view
        returns (uint256 quoteAmount)
    {
        quoteAmount = price;
    }

    function quoteToken() external view returns (address) {
        return tokenAsQuote;
    }
}
