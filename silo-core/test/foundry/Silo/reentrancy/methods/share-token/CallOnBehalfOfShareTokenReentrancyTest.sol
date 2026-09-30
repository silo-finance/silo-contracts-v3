// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareTokenInitializable} from "silo-core/contracts/interfaces/IShareTokenInitializable.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";

contract CallOnBehalfOfShareTokenReentrancyTest is ShareTokenMethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert as expected (protected and debt share tokens)"));
        _executeForAllShareTokens(_ensureItWillRevertAsExpected);
    }

    function verifyReentrancy() external {
        _executeForAllShareTokens(_ensureItWillRevertAsExpected);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "callOnBehalfOfShareToken(address,uint256,uint8,bytes)";
    }

    function _ensureItWillRevertAsExpected(address _token) internal {
        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        IShareTokenInitializable(_token).callOnBehalfOfShareToken(address(this), 0, ISilo.CallType.Call, "");
    }
}
