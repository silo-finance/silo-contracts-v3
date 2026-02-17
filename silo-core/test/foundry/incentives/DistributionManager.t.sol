// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DistributionManager} from "silo-core/contracts/incentives/base/DistributionManager.sol";

contract DistributionManagerImpl is DistributionManager {
    constructor(address _notifier) DistributionManager(msg.sender, _notifier) {}

    // make is public just for QA
    function shareToken() public view returns (address) {
        return address(_shareToken());
    }
}

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc DistributionManagerTest
*/
contract DistributionManagerTest is Test {
    // this test is for coverage purposers
    function test_shareToken() public {
        address notifier = makeAddr("Notifier");
        DistributionManagerImpl distributionManager = new DistributionManagerImpl(notifier);

        assertEq(
            distributionManager.shareToken(), notifier, "shareToken should be notifier for original implementation"
        );
    }
}
