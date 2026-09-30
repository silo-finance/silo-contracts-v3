// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

contract HookReceiverMock is CommonBase, StdCheats {
    address public immutable ADDRESS;

    constructor(address _hook) {
        ADDRESS = _hook == address(0) ? makeAddr("HookReceiverMockAddr") : _hook;
    }

    function hookReceiverConfigMock(uint24 _hooksBefore, uint24 _hooksAfter) public {
        bytes memory data = abi.encodeWithSelector(IHookReceiver.hookReceiverConfig.selector);

        vm.mockCall(ADDRESS, data, abi.encode(_hooksBefore, _hooksAfter));

        vm.expectCall(ADDRESS, data);
    }

    function afterTokenTransferMock(
        address _silo,
        uint256 _action,
        address _sender,
        uint256 _senderBalance,
        address _recipient,
        uint256 _recipientBalance,
        uint256 _totalSupply,
        uint256 _amount
    ) public {
        bytes memory inputAndOutput =
            abi.encodePacked(_sender, _recipient, _amount, _senderBalance, _recipientBalance, _totalSupply);

        bytes memory data =
            abi.encodeWithSelector(IHookReceiver.afterAction.selector, _silo, _action, inputAndOutput);

        vm.mockCall(ADDRESS, data, abi.encode(0));
        vm.expectCall(ADDRESS, data);
    }
}
