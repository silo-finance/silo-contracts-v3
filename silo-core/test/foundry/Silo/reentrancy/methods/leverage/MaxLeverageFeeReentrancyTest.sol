// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {RevenueModule} from "silo-core/contracts/leverage/modules/RevenueModule.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract MaxLeverageFeeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "MAX_LEVERAGE_FEE()";
    }

    function _ensureItWillNotRevert() internal view {
        RevenueModule leverage = _getLeverage();
        leverage.MAX_LEVERAGE_FEE();
    }

    function _getLeverage() internal view returns (RevenueModule) {
        return RevenueModule(TestStateLib.leverageRouter());
    }
}
