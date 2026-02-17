// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareTokenInitializable} from "silo-core/contracts/interfaces/IShareTokenInitializable.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";

contract InitializeReentrancyTest is ShareTokenMethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert (all share tokens)"));
        _executeForAllShareTokens(_ensureItWillNotRevert);
    }

    function verifyReentrancy() external {
        _executeForAllShareTokens(_ensureItWillNotRevert);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "initialize(address,address,uint24)";
    }

    function _ensureItWillNotRevert(address _token) internal {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        IShareTokenInitializable(_token).initialize(ISilo(address(this)), address(this), uint24(100));
    }
}
