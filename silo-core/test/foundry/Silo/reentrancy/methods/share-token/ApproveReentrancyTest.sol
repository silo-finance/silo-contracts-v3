// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ShareToken} from "silo-core/contracts/utils/ShareToken.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";

contract ApproveReentrancyTest is ShareTokenMethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert (all share tokens)"));
        _executeForAllShareTokens(_ensureItWillNotRevert);
    }

    function verifyReentrancy() external {
        _executeForAllShareTokens(_ensureItWillRevert);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "approve(address,uint256)";
    }

    function _ensureItWillNotRevert(address _token) internal {
        ShareToken(_token).approve(address(this), 100);
    }

    function _ensureItWillRevert(address _token) internal {
        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        ShareToken(_token).approve(address(this), 100);
    }
}
