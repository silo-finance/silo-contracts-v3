// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract MaxMintWithTypeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "maxMint(address,uint8)";
    }

    function _ensureItWillNotRevert() internal {
        address anyAddr = makeAddr("Any address");

        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo0().maxMint(anyAddr);
        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo1().maxMint(anyAddr);

        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo0().maxMint(anyAddr);
        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo1().maxMint(anyAddr);
    }
}
