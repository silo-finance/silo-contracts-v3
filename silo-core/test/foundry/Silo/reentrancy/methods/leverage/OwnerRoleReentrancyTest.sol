// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract OwnerRoleReentrancyTest is MethodReentrancyTest {
    function callMethod() external view {
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "OWNER_ROLE()";
    }

    function _ensureItWillNotRevert() internal view {
        LeverageRouter router = _getLeverageRouter();
        router.OWNER_ROLE();
    }

    function _getLeverageRouter() internal view returns (LeverageRouter) {
        return LeverageRouter(TestStateLib.leverageRouter());
    }
}
