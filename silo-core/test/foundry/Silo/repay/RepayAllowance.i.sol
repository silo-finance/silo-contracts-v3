// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test --ffi -vv --mc RepayAllowanceTest
*/
contract RepayAllowanceTest is SiloLittleHelper, Test {
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

    function _setUp() private {
        siloConfig = _setUpLocalFixture();

        _deposit(ASSETS * 10, BORROWER);
        _depositForBorrow(ASSETS, DEPOSITOR);
        _borrow(ASSETS, BORROWER);
    }

    /*
    forge test --ffi -vv --mt test_repay_WithoutAllowance
    */
    function test_repay_WithoutAllowance() public {
        _setUp();

        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));

        assertEq(IShareToken(debtShareToken).balanceOf(BORROWER), ASSETS, "BORROWER debt before");

        uint256 toRepay = ASSETS / 2;

        token1.mint(address(this), toRepay);
        token1.approve(address(silo1), toRepay);
        silo1.repay(toRepay, BORROWER);

        assertEq(IShareToken(debtShareToken).balanceOf(BORROWER), ASSETS - toRepay, "BORROWER debt after reduced");
    }
}
