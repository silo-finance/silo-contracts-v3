// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test --ffi -vv --mc BorrowAllowanceTest
*/
contract BorrowAllowanceTest is SiloLittleHelper, Test {
    uint256 internal constant ASSETS = 1e18;

    address immutable DEPOSITOR;
    address immutable RECEIVER;
    address immutable BORROWER;

    ISiloConfig siloConfig;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        RECEIVER = makeAddr("Other");
        BORROWER = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        _deposit(ASSETS * 10, BORROWER);
        _depositForBorrow(ASSETS, DEPOSITOR);
    }

    /*
    forge test --ffi -vv --mt test_borrow_WithoutAllowance_1
    */
    function test_borrow_WithoutAllowance_1() public {
        vm.expectRevert(abi.encodeWithSelector(IShareToken.AmountExceedsAllowance.selector));
        silo1.borrow(ASSETS, RECEIVER, BORROWER);
    }

    /*
    forge test --ffi -vv --mt test_borrow_WithAllowance
    */
    function test_borrow_WithAllowance() public {
        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));

        vm.prank(BORROWER);
        ShareDebtToken(debtShareToken).setReceiveApproval(address(this), ASSETS);

        assertEq(IShareToken(debtShareToken).balanceOf(BORROWER), 0, "BORROWER no debt before");
        assertEq(IShareToken(debtShareToken).balanceOf(DEPOSITOR), 0, "DEPOSITOR no debt before");
        assertEq(IShareToken(debtShareToken).balanceOf(RECEIVER), 0, "RECEIVER no debt before");

        assertEq(token1.balanceOf(RECEIVER), 0, "RECEIVER no tokens before");

        silo1.borrow(ASSETS / 2, RECEIVER, BORROWER);

        assertEq(IShareToken(debtShareToken).balanceOf(BORROWER), ASSETS / 2, "BORROWER has debt after");
        assertEq(IShareToken(debtShareToken).balanceOf(DEPOSITOR), 0, "DEPOSITOR no debt after");
        assertEq(IShareToken(debtShareToken).balanceOf(RECEIVER), 0, "RECEIVER no debt after");

        assertEq(token1.balanceOf(RECEIVER), ASSETS / 2, "RECEIVER got tokens after");

        assertEq(
            ShareDebtToken(debtShareToken).receiveAllowance(address(this), BORROWER),
            ASSETS / 2,
            "allowance reduced"
        );
    }
}
