// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract PreviewRedeemWithTypeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "previewRedeem(uint256,uint8)";
    }

    function _ensureItWillNotRevert() internal view {
        uint256 someAmount = 1000_0000e18;

        TestStateLib.silo0().previewRedeem(someAmount, ISilo.CollateralType.Collateral);
        TestStateLib.silo1().previewRedeem(someAmount, ISilo.CollateralType.Collateral);

        TestStateLib.silo0().previewRedeem(someAmount, ISilo.CollateralType.Protected);
        TestStateLib.silo1().previewRedeem(someAmount, ISilo.CollateralType.Protected);
    }
}
