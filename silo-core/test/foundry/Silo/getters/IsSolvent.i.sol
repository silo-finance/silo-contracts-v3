// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IERC20R} from "silo-core/contracts/interfaces/IERC20R.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc IsSolventTest
*/
contract IsSolventTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_isSolvent_onDebtTransfer
    this test covers the bug when wrong configs are fetched after debt transfer
    */
    function test_isSolvent_onDebtTransfer() public {
        uint256 assets = 1e18;
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");
        address recipient = makeAddr("Recipient");

        _deposit(assets, borrower);
        _depositForBorrow(assets, depositor);

        _deposit(2, recipient);

        _borrow(assets / 2, borrower);

        ISilo collateralSilo = silo0;

        (, address collateralShareToken,) = collateralSilo.config().getShareTokens(address(collateralSilo));
        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        vm.prank(recipient);
        IERC20R(debtShareToken).setReceiveApproval(borrower, 1);

        // it does not matter which silo we will call for checking borrower solvency
        vm.expectCall(address(silo1), abi.encodeWithSelector(ISilo.isSolvent.selector, recipient));
        vm.expectCall(debtShareToken, abi.encodeWithSelector(IERC20.balanceOf.selector, recipient));

        vm.expectCall(
            collateralShareToken, abi.encodeWithSelector(IShareToken.balanceOfAndTotalSupply.selector, recipient)
        );

        vm.prank(borrower);
        IShareToken(debtShareToken).transfer(recipient, 1);
    }

    /*
    forge test -vv --ffi --mt test_isSolvent_RecipientNotSolventAfterTransfer
    */
    function test_isSolvent_RecipientNotSolventAfterTransfer() public {
        uint256 assets = 1e18;
        address depositor = makeAddr("Depositor");
        address borrower = makeAddr("Borrower");
        address recipient = makeAddr("Recipient");

        _deposit(assets, borrower);
        _depositForBorrow(assets, depositor);

        _borrow(assets / 2, borrower);

        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        vm.prank(recipient);
        IERC20R(debtShareToken).setReceiveApproval(borrower, 1);

        vm.prank(borrower);
        vm.expectRevert(IShareToken.RecipientNotSolventAfterTransfer.selector);
        IShareToken(debtShareToken).transfer(recipient, 1);
    }
}
