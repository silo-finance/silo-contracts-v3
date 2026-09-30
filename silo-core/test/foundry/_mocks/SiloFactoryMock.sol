// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";

contract SiloFactoryMock is Test {
    address public immutable ADDRESS;

    constructor(address _siloConfig) {
        ADDRESS = _siloConfig == address(0) ? makeAddr("SiloFactoryMock") : _siloConfig;
    }

    function getFeeReceiversMock(address _silo, address _dao, address _deployer) external {
        bytes memory data = abi.encodeWithSelector(ISiloFactory.getFeeReceivers.selector, _silo);

        vm.mockCall(ADDRESS, data, abi.encode(_dao, _deployer));
        vm.expectCall(ADDRESS, data);
    }
}
