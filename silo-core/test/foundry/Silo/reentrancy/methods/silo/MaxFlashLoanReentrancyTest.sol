// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract MaxFlashLoanReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "maxFlashLoan(address)";
    }

    function _ensureItWillNotRevert() internal view {
        address token0 = TestStateLib.token0();
        address token1 = TestStateLib.token1();

        IERC3156FlashLender(address(TestStateLib.silo0())).maxFlashLoan(token0);
        IERC3156FlashLender(address(TestStateLib.silo1())).maxFlashLoan(token0);

        IERC3156FlashLender(address(TestStateLib.silo0())).maxFlashLoan(token1);
        IERC3156FlashLender(address(TestStateLib.silo1())).maxFlashLoan(token1);
    }
}
