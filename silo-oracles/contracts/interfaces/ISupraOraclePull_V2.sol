// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ISupraOraclePull_V2 {
    ///@notice Helper function to check for the address of SupraSValueFeed contract
    function checkSupraSValueFeed() external view returns (address);
}
