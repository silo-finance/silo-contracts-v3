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
    address immutable DEPOSITOR;
    address immutable BORROWER;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        BORROWER = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_maxRepayShares_noDebt
    */
    function test_maxRepayShares_noDebt() public {
        uint256 maxRepayShares = silo1.maxRepayShares(BORROWER);
        assertEq(maxRepayShares, 0, "no debt - nothing to repay");

        _depositForBorrow(11e18, BORROWER);

        _assertBorrowerHasNoDebt();
    }

    /*
    forge test -vv --ffi --mt test_maxRepayShares_withDebt
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_maxRepayShares_withDebt_fuzz(uint128 _collateral) public {
        uint256 toBorrow = _collateral / 3;
        _createDebt(_collateral, toBorrow);

        uint256 maxRepayShares = silo1.maxRepayShares(BORROWER);
        assertEq(maxRepayShares, toBorrow, "max repay is what was BORROWER if no interest");

        _repayShares(maxRepayShares, maxRepayShares, BORROWER);
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

        uint256 maxRepayShares = silo1.maxRepayShares(BORROWER);
        assertEq(maxRepayShares, shares, "shares are always the same");

        token1.setOnDemand(true);
        _repayShares(1, maxRepayShares, BORROWER);
        _assertBorrowerHasNoDebt();
    }

    function _createDebt(uint256 _collateral, uint256 _toBorrow) internal returns (uint256 shares) {
        vm.assume(_collateral > 0);
        vm.assume(_toBorrow > 0);

        _depositForBorrow(_collateral, DEPOSITOR);
        _deposit(_collateral, BORROWER);

        shares = _borrow(_toBorrow, BORROWER);

        _ensureBorrowerHasDebt();
    }

    function _ensureBorrowerHasDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        assertGt(silo1.maxRepayShares(BORROWER), 0, "expect debt");
        assertGt(IShareToken(debtShareToken).balanceOf(BORROWER), 0, "expect debtShareToken balance > 0");
    }

    function _assertBorrowerHasNoDebt() internal view {
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        assertEq(silo1.maxRepayShares(BORROWER), 0, "expect maxRepayShares to be 0");
        assertEq(IShareToken(debtShareToken).balanceOf(BORROWER), 0, "expect debtShareToken balanace to be 0");
    }
}
