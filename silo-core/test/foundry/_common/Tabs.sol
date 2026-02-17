// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

abstract contract Tabs {
    string internal constant _TABS = "   ";

    function _tabs(uint256 _t) internal pure returns (string memory tabs) {
        for (uint256 i = 0; i < _t; i++) {
            tabs = string.concat(tabs, _TABS);
        }
    }
    
    function _tabs(uint256 _t, string memory _s) internal pure returns (string memory s) {
        for (uint256 i = 0; i < _t; i++) {
            s = string.concat(s, _TABS);
        }

        s = string.concat(s, _s);
    }
}
