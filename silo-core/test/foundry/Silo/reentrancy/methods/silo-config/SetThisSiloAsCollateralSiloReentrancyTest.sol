// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract SetThisSiloAsCollateralSiloReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert (permissions test)"));
        ISiloConfig config = TestStateLib.siloConfig();

        vm.expectRevert(ISilo.Deprecated.selector);
        config.setThisSiloAsCollateralSilo(address(0));
    }

    function verifyReentrancy() external {
        ISiloConfig config = TestStateLib.siloConfig();

        vm.expectRevert(ISilo.Deprecated.selector);
        config.setThisSiloAsCollateralSilo(address(0));
    }

    function methodDescription() external pure returns (string memory description) {
        description = "setThisSiloAsCollateralSilo(address)";
    }
}
