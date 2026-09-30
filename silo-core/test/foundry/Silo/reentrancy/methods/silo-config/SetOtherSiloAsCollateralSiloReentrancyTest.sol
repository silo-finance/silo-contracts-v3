// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract SetOtherSiloAsCollateralSiloReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert (permissions test)"));
        ISiloConfig config = TestStateLib.siloConfig();

        vm.expectRevert(ISiloConfig.OnlySilo.selector);
        config.setOtherSiloAsCollateralSilo(address(0));
    }

    function verifyReentrancy() external {
        ISiloConfig config = TestStateLib.siloConfig();

        vm.expectRevert(ISiloConfig.OnlySilo.selector);
        config.setOtherSiloAsCollateralSilo(address(0));
    }

    function methodDescription() external pure returns (string memory description) {
        description = "setOtherSiloAsCollateralSilo(address)";
    }
}
