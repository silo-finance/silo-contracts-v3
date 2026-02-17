// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract AccrueInterestForConfigReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "accrueInterestForConfig(address,uint256,uint256)";
    }

    function _ensureItWillNotRevert() internal {
        ISiloConfig config = TestStateLib.siloConfig();

        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        ISiloConfig.ConfigData memory config0 = config.getConfig(address(silo0));

        vm.prank(address(config));
        silo0.accrueInterestForConfig(config0.interestRateModel, 1e17, 1e17);

        vm.prank(address(config));
        silo1.accrueInterestForConfig(config0.interestRateModel, 1e17, 1e17);
    }
}
