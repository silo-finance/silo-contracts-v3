// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ShareToken} from "silo-core/contracts/utils/ShareToken.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";

contract TotalSupplyReentrancyTest is ShareTokenMethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert (all share tokens)"));
        _executeForAllShareTokens(_ensureItWillNotRevert);
    }

    function verifyReentrancy() external {
        _executeForAllShareTokens(_ensureItWillNotRevert);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "totalSupply()";
    }

    function _ensureItWillNotRevert(address _token) internal view {
        ShareToken(_token).totalSupply();
    }
}
