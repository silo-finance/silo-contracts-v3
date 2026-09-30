// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {MintableToken} from "../../_common/MintableToken.sol";

contract WETH {
    MintableToken immutable WRAPPED;

    constructor(MintableToken _wrapped) {
        WRAPPED = _wrapped;
    }

    function deposit() external payable {
        WRAPPED.mint(msg.sender, msg.value);
    }
}
