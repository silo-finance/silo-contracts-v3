// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract GetDebtShareTokenAndAssetReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert only for wrong silo"));
        _ensureItWillRevertAsExpected();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertAsExpected();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "getDebtShareTokenAndAsset(address)";
    }

    function _ensureItWillRevertAsExpected() internal {
        ISiloConfig config = TestStateLib.siloConfig();
        address silo0 = address(TestStateLib.silo0());
        address silo1 = address(TestStateLib.silo1());
        address wrongSilo = makeAddr("Wrong silo");

        config.getDebtShareTokenAndAsset(silo0);
        config.getDebtShareTokenAndAsset(silo1);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        config.getDebtShareTokenAndAsset(wrongSilo);
    }
}
