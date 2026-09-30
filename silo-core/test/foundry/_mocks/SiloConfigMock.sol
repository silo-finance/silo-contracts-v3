// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";

contract SiloConfigMock is Test {
    address public immutable ADDRESS;

    constructor(address _siloConfig) {
        ADDRESS = _siloConfig == address(0) ? makeAddr("SiloConfigMock") : _siloConfig;
    }

    function getFeesWithAssetMock(
        address _silo,
        uint256 _daoFee,
        uint256 _deployerFee,
        uint256 _flashloanFee,
        address _asset
    ) external {
        bytes memory data = abi.encodeWithSelector(ISiloConfig.getFeesWithAsset.selector, _silo);

        vm.mockCall(ADDRESS, data, abi.encode(_daoFee, _deployerFee, _flashloanFee, _asset));
        vm.expectCall(ADDRESS, data);
    }

    function getConfigMock(address _silo, ISiloConfig.ConfigData memory _configData) external {
        bytes memory data = abi.encodeWithSelector(ISiloConfig.getConfig.selector, _silo);

        vm.mockCall(ADDRESS, data, abi.encode(_configData));
        vm.expectCall(ADDRESS, data);
    }

    function getSilosMock(address _silo0, address _silo1) external {
        bytes memory data = abi.encodeWithSelector(ISiloConfig.getSilos.selector);

        vm.mockCall(ADDRESS, data, abi.encode(_silo0, _silo1));
        vm.expectCall(ADDRESS, data);
    }

    function reentrancyGuardEnteredMock(bool _status) external {
        bytes memory data = abi.encodeWithSelector(ICrossReentrancyGuard.reentrancyGuardEntered.selector);

        vm.mockCall(ADDRESS, data, abi.encode(_status));
        vm.expectCall(ADDRESS, data);
    }

    function turnOnReentrancyProtectionMock() external {
        bytes memory data = abi.encodeWithSelector(ICrossReentrancyGuard.turnOnReentrancyProtection.selector);

        vm.mockCall(ADDRESS, data, abi.encode(0));
        vm.expectCall(ADDRESS, data);
    }

    function turnOffReentrancyProtectionMock() external {
        bytes memory data = abi.encodeWithSelector(ICrossReentrancyGuard.turnOffReentrancyProtection.selector);

        vm.mockCall(ADDRESS, data, abi.encode(0));
        vm.expectCall(ADDRESS, data);
    }
}
