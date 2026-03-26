// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IBankModule} from "./IBankModule.sol";

contract InjectiveTokenAdapter {
    IBankModule public constant BANK_MODULE = IBankModule(address(0x64));
    address public immutable TOKEN;

    constructor(address _token) {
        TOKEN = _token;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return BANK_MODULE.balanceOf(TOKEN, _account);
    }

    function decimals() external view returns (uint8) {
        (,, uint8 d) = BANK_MODULE.metadata(TOKEN);
        return d;
    }

    function symbol() external view returns (string memory) {
        (, string memory s,) = BANK_MODULE.metadata(TOKEN);
        return s;
    }

    function totalSupply() external view returns (uint256) {
        return BANK_MODULE.totalSupply(TOKEN);
    }
}
