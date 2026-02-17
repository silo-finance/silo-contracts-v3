// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract MintTokenReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert"));
        _ensureItWillRevertWithOnlySilo();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertWithOnlySilo();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "mint(address,address,uint256)";
    }

    function _ensureItWillRevertWithOnlySilo() internal {
        address silo0 = address(TestStateLib.silo0());
        vm.expectRevert(IShareToken.OnlySilo.selector);
        IShareToken(silo0).mint(address(1), address(2), 3);

        address silo1 = address(TestStateLib.silo1());
        vm.expectRevert(IShareToken.OnlySilo.selector);
        IShareToken(silo1).mint(address(1), address(2), 3);
    }
}
