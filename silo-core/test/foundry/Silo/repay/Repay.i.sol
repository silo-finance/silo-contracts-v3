// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc RepayTest
*/
contract RepayTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    event Repay(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_repay_zeros
    */
    function test_repay_zeros() public {
        vm.expectRevert(ISilo.InputZeroShares.selector);
        silo0.repay(0, address(0));
    }

    /*
    forge test -vv --ffi --mt test_repay_fromZeroAddress
    */
    function test_repay_fromZeroAddress() public {
        // for some reason we not bale to check for this error: Error != expected error: NH{q != Arithmetic over/underflow
        vm.expectRevert();
        silo0.repay(1, address(0));
    }

    /*
    forge test -vv --ffi --mt test_repay_whenNoDebt
    */
    function test_repay_whenNoDebt() public {
        address borrower = address(this);
        uint256 amount = 1;

        token0.mint(address(this), amount);
        token0.approve(address(silo0), amount);
        // for some reason we not bale to check for this error: Error != expected error: NH{q != Arithmetic over/underflow
        vm.expectRevert(); // "Arithmetic over/underflow";
        silo0.repay(amount, borrower);
    }

    /*
    forge test -vv --ffi --mt test_repay_throwZeroShares
    */
    function test_repay_throwZeroShares() public {
        uint128 assets = 1; // after interest this is to small to convert to shares
        address borrower = makeAddr("Borrower");

        _createDebt(assets, borrower);
        vm.warp(block.timestamp + 50 * 365 days); // interest must be big, so conversion 1 asset => share be 0

        vm.expectRevert(ISilo.ReturnZeroShares.selector);
        silo1.repay(assets, borrower);
    }

    /*
    forge test -vv --ffi --mt test_repay_tinyAmount
    */
    function test_repay_tinyAmount() public {
        uint128 assets = 1;
        address borrower = makeAddr("Borrower");

        _createDebt(assets, borrower);

        _repay(assets, borrower);
    }

    /*
    forge test -vv --ffi --mt test_repay_partialWithInterest
    */
    function test_repay_partialWithInterest() public {
        uint128 assets = 10;
        address borrower = makeAddr("Borrower");

        _createDebt(assets, borrower);
        vm.warp(block.timestamp + 1 days);

        _repay(assets, borrower);
    }

    /*
    forge test -vv --ffi --mt test_repay_tooMuch
    */
    function test_repay_tooMuch() public {
        uint128 assets = 1e18;
        uint256 assetsToRepay = type(uint256).max;
        address borrower = address(this);

        _createDebt(assets, borrower);
        _mintTokens(token1, assets * 2, borrower);

        vm.warp(block.timestamp + 1 days);

        token1.approve(address(silo1), assetsToRepay);

        uint256 maxRepay = silo1.maxRepay(borrower);
        uint256 shares = silo1.previewRepay(maxRepay);

        vm.expectEmit(address(silo1));
        emit Repay(address(this), borrower, maxRepay, shares);

        silo1.repay(assetsToRepay, borrower);

        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "debt fully repaid");
    }

    /*
    forge test -vv --ffi --mt test_repayShares_fullNoInterest_noDust
    */
    function test_repayShares_fullNoInterest_noDust() public {
        uint128 assets = 1e18;
        address borrower = makeAddr("Borrower");

        uint256 shares = _createDebt(assets, borrower);

        uint256 assetsToRepay = silo1.previewRepayShares(shares);
        assertEq(assetsToRepay, assets, "previewRepay == assets == allowance => when no interest");

        _repayShares(assets, shares, borrower);

        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "debt fully repaid");

        assertEq(token1.allowance(borrower, address(silo1)), 0, "NO allowance dust");
    }

    /*
    forge test -vv --ffi --mt test_repayShares_fullWithInterest_noDust
    */
    function test_repayShares_fullWithInterest_noDust() public {
        uint128 assets = 1e18;
        address borrower = makeAddr("Borrower");

        uint256 shares = _createDebt(assets, borrower);
        vm.warp(block.timestamp + 1 days);

        uint256 interest = 11684166722553653; // interest less when more collateral
        uint256 assetsToRepay = silo1.previewRepayShares(shares);
        assertEq(assetsToRepay, 1e18 + interest, "assets with interest");

        _repayShares(assetsToRepay, shares, borrower);

        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "debt fully repaid");

        assertEq(token1.allowance(borrower, address(silo1)), 0, "NO allowance dust");
    }

    /*
    forge test -vv --ffi --mt test_repayShares_insufficientAllowance
    */
    function test_repayShares_insufficientAllowance() public {
        uint128 assets = 1e18;
        address borrower = makeAddr("Borrower");

        uint256 shares = _createDebt(assets, borrower);
        vm.warp(block.timestamp + 1 days);

        uint256 previewRepay = silo1.previewRepayShares(shares);

        // after previewRepayShares we move time, so we will not be able to repay all
        vm.warp(block.timestamp + 1 days);

        uint256 currentPreview = silo1.previewRepayShares(shares);

        _repayShares(
            previewRepay, // this is our approval, it is less than `shares`
            shares, // this is what we want to repay
            borrower,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, silo1, previewRepay, currentPreview
            )
        );
    }

    /*
    forge test -vv --ffi --mt test_repayShares_notFullWithInterest_withDust
    */
    function test_repayShares_notFullWithInterest_withDust() public {
        uint128 assets = 1e18;
        address borrower = makeAddr("Borrower");

        uint256 shares = _createDebt(assets, borrower);
        vm.warp(block.timestamp + 1 days);

        uint256 interest = 11684166722553653; // interest less when more collateral
        uint256 previewRepay = silo1.previewRepayShares(shares);

        // after previewRepayShares we move time, so we will not be able to repay all
        vm.warp(block.timestamp + 1 days);

        _repayShares(previewRepay + interest * 3, shares, borrower);

        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "debt fully repaid");

        // 5697763189689604 is just copy/paste, IRM model QA should test if interest are correct
        uint256 dust = 5697763189689604;
        assertEq(token1.allowance(borrower, address(silo1)), dust, "allowance dust");
    }

    /*
    forge test -vv --ffi --mt test_repay_twice
    */
    function test_repay_twice() public {
        uint128 assets = 1e18;
        address borrower = makeAddr("Borrower");

        _createDebt(assets, borrower);

        vm.warp(block.timestamp + 1 days);
        _repay(assets / 2, borrower);

        vm.warp(block.timestamp + 1 days);
        _repay(assets / 2, borrower);

        (,, address debtShareToken) = siloConfig.getShareTokens(address(silo1));
        uint256 interestLeft = 12011339784578816; // interest smaller for one token
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), interestLeft, "interest left");
    }
}
