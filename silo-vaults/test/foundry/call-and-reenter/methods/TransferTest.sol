// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {MethodReentrancyTest} from "silo-core/test/foundry/Silo/reentrancy/methods/MethodReentrancyTest.sol";
import {TestStateLib} from "silo-vaults/test/foundry/call-and-reenter/TestState.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";
import {ErrorsLib} from "silo-vaults/contracts/libraries/ErrorsLib.sol";

contract TransferTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it reverts as expected");

        ISiloVault vault = TestStateLib.vault();

        address recipient = makeAddr("recipient");

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 100e18));
        vault.transfer(recipient, 100e18);
    }

    function verifyReentrancy() external {
        ISiloVault vault = TestStateLib.vault();

        address recipient = makeAddr("recipient");

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.ReentrancyError.selector));
        vault.transfer(recipient, 100e18);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "transfer(address,uint256)";
    }
}
