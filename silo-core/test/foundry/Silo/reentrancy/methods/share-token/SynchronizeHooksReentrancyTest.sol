// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ShareToken} from "silo-core/contracts/utils/ShareToken.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";

contract SynchronizeHooksReentrancyTest is ShareTokenMethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert as expected (all share tokens)"));
        _executeForAllShareTokens(_ensureItWillRevertOnlySilo);
    }

    function verifyReentrancy() external {
        _executeForAllShareTokens(_ensureItWillRevertOnlySilo);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "synchronizeHooks(uint24,uint24)";
    }

    function _ensureItWillRevertOnlySilo(address _token) internal {
        vm.expectRevert(IShareToken.OnlySilo.selector);
        ShareToken(_token).synchronizeHooks(uint24(1), uint24(1));
    }
}
