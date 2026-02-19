// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc MaxWithdrawTest
*/
contract MaxWithdrawCommon is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    address immutable DEPOSITOR;
    address immutable BORROWER;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        BORROWER = makeAddr("Borrower");
    }

    function _createDebtOnSilo1(uint256 _collateral, uint256 _toBorrow) internal {
        vm.assume(_toBorrow > 0);
        vm.assume(_collateral > _toBorrow);

        _depositForBorrow(_collateral, DEPOSITOR);
        _deposit(_collateral, BORROWER);
        uint256 maxBorrow = silo1.maxBorrow(BORROWER);
        vm.assume(maxBorrow > 0);

        uint256 assets = _toBorrow > maxBorrow ? maxBorrow : _toBorrow;
        _borrow(assets, BORROWER);

        emit log_named_uint("[_createDebtSilo1] _collateral", _collateral);
        emit log_named_uint("[_createDebtSilo1] maxBorrow", maxBorrow);
        emit log_named_uint("[_createDebtSilo1] _toBorrow", _toBorrow);
        emit log_named_uint("[_createDebtSilo1] borrowed", assets);

        emit log_named_decimal_uint("[_createDebtSilo1] LTV after borrow", silo1.getLtv(BORROWER), 16);
        assertEq(silo0.getLtv(BORROWER), silo1.getLtv(BORROWER), "LTV should be the same on both silos");

        _ensureBorrowerHasDebt(silo1, BORROWER);
    }

    function _createDebtOnSilo0(uint256 _collateral, uint256 _toBorrow) internal {
        vm.assume(_toBorrow > 0);
        vm.assume(_collateral > _toBorrow);

        address otherBorrower = makeAddr("some other BORROWER");

        _deposit(_collateral, DEPOSITOR);
        _depositForBorrow(_collateral, otherBorrower);
        uint256 maxBorrow = silo0.maxBorrow(otherBorrower);
        vm.assume(maxBorrow > 0);

        uint256 assets = _toBorrow > maxBorrow ? maxBorrow : _toBorrow;
        vm.prank(otherBorrower);
        silo0.borrow(assets, otherBorrower, otherBorrower);

        emit log_named_uint("[_createDebtSilo0] _collateral", _collateral);
        emit log_named_uint("[_createDebtSilo0] maxBorrow", maxBorrow);
        emit log_named_uint("[_createDebtSilo0] _toBorrow", _toBorrow);
        emit log_named_uint("[_createDebtSilo0] borrowed", assets);

        emit log_named_decimal_uint("[_createDebtSilo0] LTV after borrow", silo0.getLtv(otherBorrower), 16);
        assertEq(silo0.getLtv(otherBorrower), silo1.getLtv(otherBorrower), "LTV should be the same on both silos");

        _ensureBorrowerHasDebt(silo0, otherBorrower);
    }

    function _ensureBorrowerHasDebt(ISilo _silo, address _borrower) internal view {
        (,, address debtShareToken) = _silo.config().getShareTokens(address(_silo));

        assertGt(_silo.maxRepayShares(_borrower), 0, "expect debt");
        assertGt(IShareToken(debtShareToken).balanceOf(_borrower), 0, "expect debtShareToken balance > 0");
    }
}
