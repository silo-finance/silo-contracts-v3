// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/ERC20.sol";

import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi -vv --mc ShareDebtTokenTest
*/
contract ShareDebtTokenTest is Test, SiloLittleHelper {
    ISiloConfig public siloConfig;
    ShareDebtToken public shareDebtToken;
    address immutable RECEIVER;

    constructor() {
        RECEIVER = makeAddr("RECEIVER");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();
        (,, address debtSToken) = siloConfig.getShareTokens(address(silo1));
        shareDebtToken = ShareDebtToken(debtSToken);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debt_decimals
    */
    function test_debt_decimals() public view {
        assertEq(
            IERC20Metadata(address(shareDebtToken)).decimals(),
            IERC20Metadata(address(token1)).decimals(),
            "expect valid debt decimals"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_address_zero
    */
    function test_debtToken_transfer_address_zero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        shareDebtToken.transfer(address(0), 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_address_zero
    */
    function test_debtToken_transfer_address_zero_withAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        shareDebtToken.transfer(address(0), 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_amountZero
    */
    function test_debtToken_transfer_amountZero_noDebt() public {
        (address collateralSenderBefore, address collateralReceiverBefore) = _getCollateralState();
        assertEq(collateralSenderBefore, address(0), "sender has no state");
        assertEq(collateralReceiverBefore, address(0), "RECEIVER has no state");

        vm.expectRevert(IShareToken.ZeroTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_transfer_amountZero_withSenderDebt
    */
    function test_transfer_amountZero_withSenderDebt() public {
        _deposit(20, address(this));
        _depositForBorrow(2, makeAddr("depositor"));
        _borrow(2, address(this));

        vm.expectRevert(IShareToken.ZeroTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 0);
    }

    function test_transfer_amountZero_withReceiverDebt() public {
        _deposit(20, RECEIVER);
        _depositForBorrow(2, makeAddr("depositor"));
        _borrow(2, RECEIVER);

        vm.expectRevert(IShareToken.ZeroTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 0);
    }

    function test_transfer_amountZero_withSenderReceiverDebt() public {
        _deposit(20, address(this));
        _deposit(20, RECEIVER);
        _depositForBorrow(20, makeAddr("depositor"));
        _borrow(2, address(this));
        _borrow(2, RECEIVER);

        vm.expectRevert(IShareToken.ZeroTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_noAllowance
    */
    function test_debtToken_transfer_noAllowance() public {
        _deposit(2, address(this));
        _depositForBorrow(2, makeAddr("depositor"));
        _borrow(1, address(this));

        vm.expectRevert(IShareToken.AmountExceedsAllowance.selector);
        shareDebtToken.transfer(RECEIVER, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_withLowAllowance
    */
    function test_debtToken_transfer_withLowAllowance() public {
        _deposit(20, address(this));
        _depositForBorrow(2, makeAddr("depositor"));
        _borrow(2, address(this));

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), 1);

        vm.expectRevert(IShareToken.AmountExceedsAllowance.selector);
        shareDebtToken.transfer(RECEIVER, 2);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_withAllowance_noCollateral
    */
    function test_debtToken_transfer_withAllowance_noCollateral() public {
        _deposit(20, address(this));
        _depositForBorrow(2, makeAddr("depositor"));
        _borrow(2, address(this));

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), 1);

        vm.expectRevert(IShareToken.RecipientNotSolventAfterTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_withAllowance_notSolvent
    */
    function test_debtToken_transfer_withAllowance_notSolvent() public {
        _deposit(20, address(this));
        _deposit(1, RECEIVER);
        _depositForBorrow(2, makeAddr("depositor"));
        _borrow(2, address(this));

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), 1);

        vm.expectRevert(IShareToken.RecipientNotSolventAfterTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_withAllowance_differentCollateral
    */
    function test_debtToken_transfer_withAllowance_differentCollateral() public {
        _deposit(20, address(this));
        _depositForBorrow(20, RECEIVER);
        _depositForBorrow(10, makeAddr("depositor"));
        _borrow(2, address(this));

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), 1);

        vm.expectRevert(IShareToken.RecipientNotSolventAfterTransfer.selector);
        shareDebtToken.transfer(RECEIVER, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_withAllowance_sameCollateral
    */
    function test_debtToken_transfer_withAllowance_sameCollateral() public {
        _deposit(20, address(this));
        _deposit(20, RECEIVER);
        _depositForBorrow(20, makeAddr("depositor"));
        _borrow(2, address(this));

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), 1);

        (address collateralSenderBefore,) = _getCollateralState();

        shareDebtToken.transfer(RECEIVER, 1);

        _assertCollateralSiloWasCopiedFromSenderToReceiver(collateralSenderBefore);
        _assertReceiverIsNotBlockedByAnything();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_withAllowance_withSameDebt
    */
    function test_debtToken_transfer_withAllowance_withSameDebt() public {
        _deposit(20, address(this));
        _deposit(20, RECEIVER);
        _depositForBorrow(20, makeAddr("depositor"));

        _borrow(2, address(this));
        _borrow(1, RECEIVER);

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), 1);

        (address collateralSenderBefore,) = _getCollateralState();

        shareDebtToken.transfer(RECEIVER, 1);

        _assertCollateralSiloWasCopiedFromSenderToReceiver(collateralSenderBefore);
        _assertReceiverIsNotBlockedByAnything();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transferAll
    */
    function test_debtToken_transferAll() public {
        uint256 toBorrow = 2;

        _deposit(20, address(this));
        _deposit(20, RECEIVER);
        _depositForBorrow(2, makeAddr("depositor"));
        _printStats(siloConfig, address(this));
        _borrow(toBorrow, address(this));

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), toBorrow);

        (address collateralSenderBefore, address collateralReceiverBefore) = _getCollateralState();
        assertEq(collateralReceiverBefore, address(0), "[transferAll] RECEIVER collateral is empty");

        shareDebtToken.transfer(RECEIVER, toBorrow);

        (address collateralSenderAfter, address collateralReceiverAfter) = _getCollateralState();

        assertEq(collateralSenderBefore, collateralSenderAfter, "[transferAll] sender history is not cleared");
        assertEq(collateralReceiverAfter, collateralSenderBefore, "[transferAll] state copied sender -> RECEIVER");

        _assertReceiverIsNotBlockedByAnything();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transfer_debtExistInOtherSilo_
    */
    function test_debtToken_transfer_debtExistInOtherSilo() public {
        uint256 toBorrow = 2;

        _deposit(20, address(this));
        _depositForBorrow(20, RECEIVER);
        _depositForBorrow(2, makeAddr("depositor"));
        _printStats(siloConfig, address(this));

        _borrow(toBorrow, address(this));

        vm.prank(RECEIVER);
        silo0.borrow(1, RECEIVER, RECEIVER);

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(address(this), toBorrow);

        vm.expectRevert(ISiloConfig.DebtExistInOtherSilo.selector);
        shareDebtToken.transfer(RECEIVER, toBorrow);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_shareDebtToken_allowance
    */
    function test_shareDebtToken_allowance() public {
        address user = makeAddr("user");
        address otherUser = makeAddr("otherUser");
        uint256 amount = 100e18;

        uint256 allowance = shareDebtToken.receiveAllowance(user, otherUser);
        assertEq(allowance, 0, "no allowance");

        vm.prank(otherUser);
        shareDebtToken.setReceiveApproval(user, amount);

        allowance = shareDebtToken.receiveAllowance(user, otherUser);
        assertEq(allowance, amount, "allowance set");

        uint256 decreaseAmount = 10e18;

        vm.prank(otherUser);
        shareDebtToken.decreaseReceiveAllowance(user, decreaseAmount);

        uint256 newAllowance = amount - decreaseAmount;

        allowance = shareDebtToken.receiveAllowance(user, otherUser);
        assertEq(allowance, newAllowance, "allowance decreased");

        uint256 increaseAmount = 20e18;

        vm.prank(otherUser);
        shareDebtToken.increaseReceiveAllowance(user, increaseAmount);

        newAllowance += increaseAmount;

        allowance = shareDebtToken.receiveAllowance(user, otherUser);
        assertEq(allowance, newAllowance, "allowance increased");

        uint256 otherAmount = 10000e18;

        vm.prank(otherUser);
        shareDebtToken.setReceiveApproval(user, otherAmount);

        allowance = shareDebtToken.receiveAllowance(user, otherUser);
        assertEq(allowance, otherAmount, "allowance overridden");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transferFrom_allowance
    */
    function test_debtToken_transferFrom_allowance() public {
        address borrower = makeAddr("Borrower");
        address spender = makeAddr("Spender");

        vm.prank(borrower);
        shareDebtToken.approve(spender, 1e18);

        vm.prank(spender);
        vm.expectRevert(IShareToken.AmountExceedsAllowance.selector);
        shareDebtToken.transferFrom(borrower, RECEIVER, 1e18);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_debtToken_transferFrom
    */
    function test_debtToken_transferFrom() public {
        address depositor = makeAddr("Depositor");
        address spender = makeAddr("Spender");
        uint256 amount = 100e18;

        _deposit(amount, depositor, ISilo.CollateralType.Collateral);
        _deposit(amount, depositor, ISilo.CollateralType.Protected);

        _depositForBorrow(amount * 2, makeAddr("any"), ISilo.CollateralType.Collateral);

        uint256 borrowAmount = 150e18;
        address borrower = depositor;

        _borrow(borrowAmount, borrower);

        vm.prank(borrower);
        shareDebtToken.approve(spender, borrowAmount);

        vm.prank(RECEIVER);
        shareDebtToken.setReceiveApproval(borrower, borrowAmount);

        vm.prank(spender);
        vm.expectRevert(IShareToken.RecipientNotSolventAfterTransfer.selector);
        shareDebtToken.transferFrom(borrower, RECEIVER, borrowAmount);

        _deposit(amount * 3, RECEIVER, ISilo.CollateralType.Collateral);

        uint256 balance = shareDebtToken.balanceOf(RECEIVER);

        assertEq(balance, 0, "RECEIVER has no debt");

        vm.prank(spender);
        shareDebtToken.transferFrom(borrower, RECEIVER, borrowAmount);

        balance = shareDebtToken.balanceOf(RECEIVER);
        assertEq(balance, borrowAmount, "RECEIVER has debt");
    }

    function _getCollateralState() private returns (address collateralSender, address collateralReceiver) {
        collateralSender = siloConfig.borrowerCollateralSilo(address(this));
        collateralReceiver = siloConfig.borrowerCollateralSilo(makeAddr("RECEIVER"));
    }

    function _assertCollateralSiloDidNotChanged(address _collateralSenderBefore, address _collateralReceiverBefore)
        private
    {
        (address collateralSenderAfter, address collateralReceiverAfter) = _getCollateralState();

        assertEq(_collateralSenderBefore, collateralSenderAfter, "[a] does not change the sender state");
        assertEq(_collateralReceiverBefore, collateralReceiverAfter, "[a] does not change the RECEIVER state");
    }

    function _assertCollateralSiloWasCopiedFromSenderToReceiver(address _collateralSenderBefore) private {
        address collateralSenderAfter = siloConfig.borrowerCollateralSilo(address(this));
        address collateralReceiverAfter = siloConfig.borrowerCollateralSilo(makeAddr("RECEIVER"));

        assertEq(_collateralSenderBefore, collateralSenderAfter, "[b] does not change the sender state");
        assertEq(_collateralSenderBefore, collateralReceiverAfter, "[b] copies state of sender to RECEIVER");
    }

    function _assertReceiverIsNotBlockedByAnything() private {
        _depositForBorrow(100, RECEIVER);
        _deposit(100, RECEIVER);
        _depositForBorrow(100, makeAddr("depositor"));
        _borrow(2, RECEIVER);

        _repay(2, RECEIVER);

        vm.prank(RECEIVER);
        silo0.withdraw(2, RECEIVER, RECEIVER);

        vm.prank(RECEIVER);
        silo1.withdraw(2, RECEIVER, RECEIVER);
    }
}
