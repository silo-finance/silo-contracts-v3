// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IUSDT {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint);
    function upgradedAddress() external view returns (address);
    function deprecated() external view returns (bool);

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transfer(address _to, uint _value) external;

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transferFrom(address _from, address _to, uint _value) external;

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function balanceOf(address who) external returns (uint);

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function approve(address _spender, uint _value) external;

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function allowance(address _owner, address _spender) external returns (uint remaining);

    // deprecate current contract in favour of a new one
    function deprecate(address _upgradedAddress) external;

    // deprecate current contract if favour of a new one
    function totalSupply() external returns (uint);

    // Issue a new amount of tokens
    // these tokens are deposited into the owner address
    //
    // @param _amount Number of tokens to be issued
    function issue(uint amount) external;

    // Redeem tokens.
    // These tokens are withdrawn from the owner address
    // if the balance must be enough to cover the redeem
    // or the call will fail.
    // @param _amount Number of tokens to be issued
    function redeem(uint amount) external;

    function setParams(uint newBasisPoints, uint newMaxFee) external;
}