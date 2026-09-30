// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract FlashFeeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "flashFee(address,uint256)";
    }

    function _ensureItWillNotRevert() internal view {
        address token0 = TestStateLib.token0();
        address token1 = TestStateLib.token1();

        IERC3156FlashLender(address(TestStateLib.silo0())).flashFee(token0, 100e18);
        IERC3156FlashLender(address(TestStateLib.silo1())).flashFee(token1, 100e18);
    }
}
