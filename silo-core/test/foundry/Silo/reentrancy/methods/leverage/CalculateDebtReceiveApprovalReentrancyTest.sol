// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract CalculateDebtReceiveApprovalReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "calculateDebtReceiveApproval(address,uint256)";
    }

    function _ensureItWillNotRevert() internal view {
        ILeverageRouter leverage = _getLeverage();
        ISilo silo = TestStateLib.silo0();
        leverage.calculateDebtReceiveApproval(silo, 1000e18);
    }

    function _getLeverage() internal view returns (ILeverageRouter) {
        return ILeverageRouter(TestStateLib.leverageRouter());
    }
}
