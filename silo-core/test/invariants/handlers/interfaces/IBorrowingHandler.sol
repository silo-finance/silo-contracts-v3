// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBorrowingHandler {
    function borrow(uint256 _assets, uint8 i, uint8 j) external;

    function borrowShares(uint256 _shares, uint8 i, uint8 j) external;

    function repay(uint256 _assets, uint8 i, uint8 j) external;

    function repayShares(uint256 _shares, uint8 i, uint8 j) external;
}
