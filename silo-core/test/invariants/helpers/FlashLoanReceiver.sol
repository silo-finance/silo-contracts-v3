// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Interfaces
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";

// Test Contracts
import {TestERC20} from "../utils/mocks/TestERC20.sol";
import {PropertiesAsserts} from "../utils/PropertiesAsserts.sol";
import {PostconditionsSpec} from "../specs/PostconditionsSpec.t.sol";

import {console} from "forge-std/console.sol";

contract MockFlashLoanReceiver is IERC3156FlashBorrower, PropertiesAsserts, PostconditionsSpec {
    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor() {}

    function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata _data)
        external
        returns (bytes32)
    {
        (uint256 amountToRepay, address sender) = abi.decode(_data, (uint256, address));

        uint256 balance = TestERC20(_token).balanceOf(address(this));

        if (balance > _amount + _fee) {
            TestERC20(_token).burn(address(this), balance - _amount - _fee);
        } else if (balance < _amount + _fee) {
            TestERC20(_token).mint(address(this), _amount + _fee - balance);
        }

        assertEq(_initiator, sender, BORROWING_HSPOST_U3);
        _setAmountBack(_token, amountToRepay, _amount + _fee);

        TestERC20(_token).approve(msg.sender, type(uint256).max);

        return _FLASHLOAN_CALLBACK;
    }

    function _setAmountBack(address _token, uint256 _amountToRepay, uint256 _amountWithFee) internal {
        if (_amountToRepay > _amountWithFee) {
            TestERC20(_token).mint(address(this), _amountToRepay - _amountWithFee);
        } else if (_amountToRepay < _amountWithFee) {
            TestERC20(_token).burn(address(this), _amountWithFee - _amountToRepay);
        }
    }
}
