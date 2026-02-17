// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc MaxRepaySharesTest
*/
contract MaxRepaySharesTest is SiloLittleHelper, Test {
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
    forge test -vv --ffi --mt test_maxRepayShares_noDebt
    */
    function test_maxRepayShares_noDebt() public {
        uint256 maxRepayShares = silo1.maxRepayShares(borrower);
        assertEq(maxRepayShares, 0, "no debt - nothing to repay");

        _depositForBorrow(11e18, borrower);

        _assertBorrowerHasNoDebt();
    }

    /*
    forge test -vv --ffi --mt test_maxRepayShares_withDebt
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxRepayShares_withDebt_fuzz(uint128 _collateral) public {
        uint256 toBorrow = _collateral / 3;
        _createDebt(_collateral, toBorrow);

        uint256 maxRepayShares = silo1.maxRepayShares(borrower);
        assertEq(maxRepayShares, toBorrow, "max repay is what was borrower if no interest");

        _repayShares(maxRepayShares, maxRepayShares, borrower);
        _assertBorrowerHasNoDebt();
    }

    /*
    forge test -vv --ffi --mt test_maxRepayShares_withInterest
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxRepayShares_withInterest_fuzz(uint128 _collateral) public {
        uint256 toBorrow = _collateral / 3;
        uint256 shares = _createDebt(_collateral, toBorrow);

        vm.warp(block.timestamp + 356 days);

        uint256 maxRepayShares = silo1.maxRepayShares(borrower);
        assertEq(maxRepayShares, shares, "shares are always the same");

        token1.setOnDemand(true);
        _repayShares(1, maxRepayShares, borrower);
        _assertBorrowerHasNoDebt();
    }

    function _createDebt(uint256 _collateral, uint256 _toBorrow) internal returns (uint256 shares) {
        vm.assume(_collateral > 0);
        vm.assume(_toBorrow > 0);

        _depositForBorrow(_collateral, depositor);
        _deposit(_collateral, borrower);

        shares = _borrow(_toBorrow, borrower);

        _ensureBorrowerHasDebt();
    }

    function _ensureBorrowerHasDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        assertGt(silo1.maxRepayShares(borrower), 0, "expect debt");
        assertGt(IShareToken(debtShareToken).balanceOf(borrower), 0, "expect debtShareToken balance > 0");
    }

    function _assertBorrowerHasNoDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        assertEq(silo1.maxRepayShares(borrower), 0, "expect maxRepayShares to be 0");
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "expect debtShareToken balanace to be 0");
    }
}
