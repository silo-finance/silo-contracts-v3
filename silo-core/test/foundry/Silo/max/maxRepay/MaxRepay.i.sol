// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc MaxRepayTest
*/
contract MaxRepayTest is SiloLittleHelper, Test {
    uint256 internal constant _REAL_ASSETS_LIMIT = type(uint128).max;

    ISiloConfig siloConfig;
    address immutable depositor;
    address immutable borrower;

    constructor() {
        depositor = makeAddr("Depositor");
        borrower = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_maxRepay_noDebt
    */
    function test_maxRepay_noDebt() public {
        uint256 maxRepay = silo1.maxRepay(borrower);
        assertEq(maxRepay, 0, "no debt - nothing to repay");

        _depositForBorrow(11e18, borrower);

        _assertBorrowerHasNoDebt();
    }

    /*
    forge test -vv --ffi --mt test_maxRepay_withDebt_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxRepay_withDebt_fuzz(uint128 _collateral) public {
        uint256 toBorrow = _collateral / 3;
        _createDebt(_collateral, toBorrow);

        uint256 maxRepay = silo1.maxRepay(borrower);
        assertEq(maxRepay, toBorrow, "max repay is what was borrower if no interest");

        _repay(maxRepay, borrower);
        _assertBorrowerHasNoDebt();
    }

    /*
    forge test -vv --ffi --mt test_maxRepay_withInterest_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxRepay_withInterest_fuzz(uint128 _collateral) public {
        uint256 toBorrow = _collateral / 3;
        _createDebt(_collateral, toBorrow);

        vm.warp(block.timestamp + 356 days);

        uint256 maxRepay = silo1.maxRepay(borrower);
        vm.assume(maxRepay > toBorrow); // we want interest

        _repay(maxRepay, borrower);
        _assertBorrowerHasNoDebt();
    }

    function _createDebt(uint256 _collateral, uint256 _toBorrow) internal {
        vm.assume(_collateral > 0);
        vm.assume(_toBorrow > 0);

        _depositForBorrow(_collateral, depositor);
        _deposit(_collateral, borrower);
        _borrow(_toBorrow, borrower);

        _ensureBorrowerHasDebt();
    }

    function _ensureBorrowerHasDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        assertGt(silo1.maxRepay(borrower), 0, "expect debt");
        assertGt(IShareToken(debtShareToken).balanceOf(borrower), 0, "expect debtShareToken balance > 0");
    }

    function _assertBorrowerHasNoDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        assertEq(silo1.maxRepay(borrower), 0, "expect maxRepay to be 0");
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "expect debtShareToken balance to be 0");
    }
}
