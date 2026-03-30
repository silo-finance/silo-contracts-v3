// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ISupraSValueFeed {
    struct priceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    function getSvalue(uint256 _pairIndex) external view returns (priceFeed memory);
}
