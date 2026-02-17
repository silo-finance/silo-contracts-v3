// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract OnDebtTransferReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert (permissions test)"));
        _ensureItWillRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "onDebtTransfer(address,address)";
    }

    function _ensureItWillRevert() internal {
        ISiloConfig config = TestStateLib.siloConfig();

        vm.expectRevert(ISiloConfig.OnlyDebtShareToken.selector);
        config.onDebtTransfer(address(0), address(0));
    }
}
