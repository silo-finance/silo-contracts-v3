// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract ConvertToSharesWithTypeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "convertToShares(uint256,uint8)";
    }

    function _ensureItWillNotRevert() internal view {
        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo0().convertToShares(100e18, ISilo.AssetType.Collateral);
        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo1().convertToShares(100e18, ISilo.AssetType.Collateral);

        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo0().convertToShares(100e18, ISilo.AssetType.Protected);
        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo1().convertToShares(100e18, ISilo.AssetType.Protected);

        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo0().convertToShares(100e18, ISilo.AssetType.Debt);
        // forge-lint: disable-next-line(unused-return)
        TestStateLib.silo1().convertToShares(100e18, ISilo.AssetType.Debt);
    }
}
