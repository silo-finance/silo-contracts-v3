// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PartialLiquidationUsdtTest} from "./PartialLiquidationUsdt.i.sol";

contract PartialLiquidationUsdtOtherWayTest is PartialLiquidationUsdtTest {
    function _getTokensAddresses() internal override returns (address tokenForSilo0, address tokenForSilo1) {
        (tokenForSilo1, tokenForSilo0) = super._getTokensAddresses();
    }
}
