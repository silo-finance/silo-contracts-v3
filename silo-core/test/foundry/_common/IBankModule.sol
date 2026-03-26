// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @dev Injective Bank Module interface
interface IBankModule {
    function mint(address,uint256) external payable returns (bool);
    function balanceOf(address,address) external view returns (uint256);
    function burn(address,uint256) external payable returns (bool);
    function transfer(address,address,uint256) external payable returns (bool);
    function totalSupply(address) external view returns (uint256);
    function metadata(address) external view returns (string memory,string memory,uint8);
    function setMetadata(string calldata,string calldata,uint8) external payable returns (bool);
}
