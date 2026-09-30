// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {DynamicKinkModel} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {IInterestRateModel} from "../../../../contracts/interfaces/IInterestRateModel.sol";

contract KinkCompatibility is DynamicKinkModel, IInterestRateModel {
    function decimals() external pure returns (uint256) {
        return 0;
    }

    function initialize(address) external pure {
        /// the only method that is not compatible with IInterestRateModel is `initialize`;
        /// this test just check if we can build it without errors if we add just one method
    }

    // below methods are compatible but they derived and needs to be overridden

    function getCompoundInterestRateAndUpdate(uint256, uint256, uint256)
        external
        pure
        override(DynamicKinkModel, IInterestRateModel)
        returns (uint256)
    {
        return 0;
    }

    function getCompoundInterestRate(address, uint256)
        external
        pure
        override(DynamicKinkModel, IInterestRateModel)
        returns (uint256)
    {
        return 0;
    }

    function getCurrentInterestRate(address, uint256)
        external
        pure
        override(DynamicKinkModel, IInterestRateModel)
        returns (uint256)
    {
        return 0;
    }
}

contract KinkCompatibilityTest is Test {
    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_compatibility -vv
    */
    function test_kink_compatibility() public {
        // it is enough just to create the contract, no need to test anything
        new KinkCompatibility();
    }
}
