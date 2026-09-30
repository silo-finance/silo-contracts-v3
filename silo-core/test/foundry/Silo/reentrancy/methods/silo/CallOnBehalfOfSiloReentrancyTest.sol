// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract CallOnBehalfOfSiloReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "callOnBehalfOfSilo(address,uint256,uint8,bytes)";
    }

    function _ensureItWillNotRevert() internal {
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();
        ISiloConfig config = TestStateLib.siloConfig();

        ISiloConfig.ConfigData memory config0 = config.getConfig(address(silo0));

        address anyAddress = makeAddr("Any address");
        bytes memory payload = abi.encodeWithSelector(IShareToken.balanceOfAndTotalSupply.selector, anyAddress);

        vm.prank(address(config0.hookReceiver));
        (bool success,) =
            silo0.callOnBehalfOfSilo(config0.protectedShareToken, 0, /* eth value */ ISilo.CallType.Call, payload);

        if (!success) revert();

        vm.prank(address(config0.hookReceiver));
        (success,) =
            silo1.callOnBehalfOfSilo(config0.protectedShareToken, 0, /* eth value */ ISilo.CallType.Call, payload);

        if (!success) revert();
    }
}
