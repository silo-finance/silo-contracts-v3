// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract Debugger {
    // payable function to allow to execute call from metamask
    function exe(address _target, bytes calldata _data) external payable {
        require(msg.value == 0);

        (bool success, bytes memory returnData) = _target.call(_data);
        require(success, string(returnData));
    }
}
