// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ShareToken} from "silo-core/contracts/utils/ShareToken.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract BurnReentrancyTest is ShareTokenMethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert as expected (all share tokens)"));
        _executeForAllShareTokens(_ensureItWillRevertOnlySilo);
    }

    function verifyReentrancy() external {
        ISiloConfig config = TestStateLib.siloConfig();

        bool entered = config.reentrancyGuardEntered();
        assertTrue(entered, "Reentrancy is not enabled on a burn");

        _executeForAllShareTokens(_ensureItWillRevertOnlySilo);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "burn(address,address,uint256)";
    }

    function _ensureItWillRevertOnlySilo(address _token) internal {
        vm.expectRevert(IShareToken.OnlySilo.selector);
        ShareToken(_token).burn(address(0), address(0), 0);
    }
}
