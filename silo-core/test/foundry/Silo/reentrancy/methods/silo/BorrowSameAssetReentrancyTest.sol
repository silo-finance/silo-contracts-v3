// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract BorrowSameAssetReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo0.borrowSameAsset(0, address(0), address(0));
    }

    function verifyReentrancy() external {
        ISilo silo0 = TestStateLib.silo0();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo0.borrowSameAsset(1000, address(0), address(0));

        ISilo silo1 = TestStateLib.silo1();

        vm.expectRevert(ISilo.Deprecated.selector);
        silo1.borrowSameAsset(1000, address(0), address(0));
    }

    function methodDescription() external pure returns (string memory description) {
        description = "borrowSameAsset(uint256,address,address)";
    }
}
