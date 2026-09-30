// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc BorrowSameAssetTest
*/
contract BorrowSameAssetTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        assertTrue(siloConfig.getConfig(address(silo0)).maxLtv != 0, "we need borrow to be allowed");
    }

    /*
    forge test -vv --ffi --mt test_borrowSameAsset_deprecated
    */
    function test_borrowSameAsset_deprecated() public {
        uint256 assets = 1e18;
        address borrower = address(this);

        _deposit(assets, borrower);

        vm.expectRevert(ISilo.Deprecated.selector);
        silo0.borrowSameAsset(1, borrower, borrower);
    }
}
