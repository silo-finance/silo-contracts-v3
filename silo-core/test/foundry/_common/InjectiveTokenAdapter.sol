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

    function decimals() external view returns (uint8 d) {
        (,, d) = BANK_MODULE.metadata(TOKEN);
        require(d != 0, "decimals not set, check InjectiveWorkaround");
    }

    function symbol() external view returns (string memory s) {
        (s,,) = BANK_MODULE.metadata(TOKEN);
    }

    function totalSupply() external view returns (uint256) {
        return BANK_MODULE.totalSupply(TOKEN);
    }
}
