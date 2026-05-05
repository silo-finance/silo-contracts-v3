// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFlatPriceOracle {
    error AddressZero();
    error TokensAreTheSame();
    error AssetNotSupported();
    error ZeroPrice();

    function initialize(uint256 _price, address _baseToken, address _quoteToken) external;
}
