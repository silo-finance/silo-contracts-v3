// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";

contract InterestRateModelMock is Test {
    address public immutable ADDRESS;

    constructor() {
        ADDRESS = makeAddr("InterestRateModelMock");
    }

    // IInterestRateModel.getCompoundInterestRate.selector: 0xcfdfcffa
    function getCompoundInterestRateMock(address _silo, uint256 _blockTimestamp, uint256 _rcomp) external {
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256(abi.encodePacked("getCompoundInterestRate(address,uint256)"))), _silo, _blockTimestamp
        );

        vm.mockCall(ADDRESS, data, abi.encode(_rcomp));
        vm.expectCall(ADDRESS, data);
    }

    // IInterestRateModel.getCompoundInterestRateAndUpdate.selector:
    function getCompoundInterestRateAndUpdateMock(uint256 _rcomp) external {
        bytes memory data = abi.encodeWithSelector(IInterestRateModel.getCompoundInterestRateAndUpdate.selector);
        vm.mockCall(ADDRESS, data, abi.encode(_rcomp));
        vm.expectCall(ADDRESS, data);
    }
}
