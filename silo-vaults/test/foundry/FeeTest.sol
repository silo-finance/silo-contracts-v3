// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {Math} from "openzeppelin5/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";

import {WAD} from "morpho-blue/libraries/MathLib.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {ErrorsLib} from "../../contracts/libraries/ErrorsLib.sol";
import {EventsLib} from "../../contracts/libraries/EventsLib.sol";
import {ConstantsLib} from "../../contracts/libraries/ConstantsLib.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";
import {CAP, NB_MARKETS, MIN_TEST_ASSETS, MAX_TEST_ASSETS} from "./helpers/BaseTest.sol";

uint256 constant FEE = 0.2 ether; // 20%

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc FeeTest -vvv
*/
contract FeeTest is IntegrationTest {
    function setUp() public override {
        super.setUp();

        _setFee(FEE);

        for (uint256 i; i < NB_MARKETS; ++i) {
            IERC4626 market = allMarkets[i];

            // Create some debt on the market to accrue interest.

            vm.prank(SUPPLIER);
            market.deposit(MAX_TEST_ASSETS, ONBEHALF);

            vm.startPrank(BORROWER);
            collateralMarkets[market].deposit(MAX_TEST_ASSETS, BORROWER);
            ISilo(address(market)).borrow(ISilo(address(market)).maxBorrow(BORROWER), BORROWER, BORROWER);
            vm.stopPrank();
        }

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFee -vvv
    */
    function testSetFee(uint256 fee) public {
        fee = bound(fee, 0, ConstantsLib.MAX_FEE);
        vm.assume(fee != vault.fee());

        vm.expectEmit(address(vault));
        emit EventsLib.SetFee(OWNER, fee);
        vm.prank(OWNER);
        vault.setFee(fee);

        assertEq(vault.fee(), fee, "fee");
    }

    function _feeShares() internal view returns (uint256) {
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 interest = totalAssetsAfter - vault.lastTotalAssets();
        uint256 feeAssets = Math.mulDiv(interest, FEE, WAD);

        return Math.mulDiv(feeAssets, vault.totalSupply() + OFFSET_POW, totalAssetsAfter - feeAssets + 1, Math.Rounding.Floor);
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testAccrueFeeWithinABlock -vvv
    */
    function testAccrueFeeWithinABlock(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS + 1, MAX_TEST_ASSETS);
        // The deposited amount is rounded down on Morpho and thus cannot be withdrawn in a block in most cases.
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited - 1);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        vm.prank(ONBEHALF);
        vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertApproxEqAbs(vault.balanceOf(FEE_RECIPIENT), 0, 1, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testDepositAccrueFee -vvv
    */
    function testDepositAccrueFee(uint256 deposited, uint256 newDeposit, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        newDeposit = bound(newDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(vault));
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);

        vm.prank(SUPPLIER);
        vault.deposit(newDeposit, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testMintAccrueFee -vvv
    */
    function testMintAccrueFee(uint256 deposited, uint256 newDeposit, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        newDeposit = bound(newDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        uint256 shares = vault.convertToShares(newDeposit);

        vm.expectEmit(address(vault));
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);

        vm.prank(SUPPLIER);
        vault.mint(shares, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeemAccrueFee -vvv
    */
    function testRedeemAccrueFee(uint256 deposited, uint256 withdrawn, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        emit log_named_uint("deposit", vault.deposit(deposited, ONBEHALF));

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");
        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);
        emit log_named_uint("feeShares", feeShares);

        uint256 shares = vault.convertToShares(withdrawn);
        emit log_named_uint("shares", shares);

        vm.expectEmit(address(vault));
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);

        vm.prank(ONBEHALF);
        vault.redeem(shares, RECEIVER, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawAccrueFee -vvv
    */
    function testWithdrawAccrueFee(
        uint256 deposited, uint256 withdrawn, uint256 blocks
    ) public {
//        (uint256 deposited, uint256 withdrawn, uint256 blocks) = (4095403546134787364927493835650276036647856, 220433025230, 496682016805733960375124471420475239754471925361033367);
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(vault));
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);

        vm.prank(ONBEHALF);
        vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testClaimRewardsAccrueFee -vvv
    */
    function testClaimRewardsAccrueFee(uint256 deposited, uint256 withdrawn, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(vault));
        // AccrueInterest(newTotalAssets: 10000418691750321042067128277 [1e28], feeShares: 83735545313645916835716363000 [8.373e28])
        // AccrueInterest(newTotalAssets: 10000418691750321042067128277 [1e28], feeShares: 83735545313645916835716363 [8.373e25])
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);

        vm.prank(ONBEHALF);
        vault.claimRewards();

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeAccrueFee -vvv
    */
    function testSetFeeAccrueFee(uint256 deposited, uint256 fee, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        fee = bound(fee, 0, FEE - 1);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(vault));
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);

        _setFee(fee);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeRecipientAccrueFee -vvv
    */
    function testSetFeeRecipientAccrueFee(uint256 deposited, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(vault));
        emit EventsLib.AccrueInterest(vault.totalAssets(), feeShares);
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets());
        emit EventsLib.SetFeeRecipient(address(1));

        vm.prank(OWNER);
        vault.setFeeRecipient(address(1));

        assertApproxEqAbs(vault.lastTotalAssets(), vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(vault.balanceOf(FEE_RECIPIENT), feeShares, "vault.balanceOf(FEE_RECIPIENT)");
        assertEq(vault.balanceOf(address(1)), 0, "vault.balanceOf(address(1))");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeNotOwner -vvv
    */
    function testSetFeeNotOwner(uint256 fee) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setFee(fee);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeMaxFeeExceeded -vvv
    */
    function testSetFeeMaxFeeExceeded(uint256 fee) public {
        fee = bound(fee, ConstantsLib.MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(ErrorsLib.MaxFeeExceeded.selector);
        vault.setFee(fee);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeAlreadySet -vvv
    */
    function testSetFeeAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setFee(FEE);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeZeroFeeRecipient -vvv
    */
    function testSetFeeZeroFeeRecipient(uint256 fee) public {
        fee = bound(fee, 1, ConstantsLib.MAX_FEE);

        vm.startPrank(OWNER);

        vault.setFee(0);
        vault.setFeeRecipient(address(0));

        vm.expectRevert(ErrorsLib.ZeroFeeRecipient.selector);
        vault.setFee(fee);

        vm.stopPrank();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetFeeRecipientAlreadySet -vvv
    */
    function testSetFeeRecipientAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setFeeRecipient(FEE_RECIPIENT);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testSetZeroFeeRecipientWithFee -vvv
    */
    function testSetZeroFeeRecipientWithFee() public {
        vm.prank(OWNER);
        vm.expectRevert(ErrorsLib.ZeroFeeRecipient.selector);
        vault.setFeeRecipient(address(0));
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testConvertToAssetsWithFeeAndInterest -vvv
    */
    function testConvertToAssetsWithFeeAndInterest(uint256 deposited, uint256 assets, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        uint256 sharesBefore = vault.convertToShares(assets);

        _forward(blocks);

        uint256 feeShares = _feeShares();
        uint256 expectedShares =
            Math.mulDiv(assets, vault.totalSupply() + feeShares + OFFSET_POW, vault.totalAssets() + 1, Math.Rounding.Floor);
        uint256 shares = vault.convertToShares(assets);

        assertEq(shares, expectedShares, "shares");
        assertLt(shares, sharesBefore, "shares decreased");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testConvertToSharesWithFeeAndInterest -vvv
    */
    function testConvertToSharesWithFeeAndInterest(uint256 deposited, uint256 shares, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        shares = bound(shares, 1, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        uint256 assetsBefore = vault.convertToAssets(shares);

        _forward(blocks);

        uint256 feeShares = _feeShares();
        uint256 expectedAssets =
            Math.mulDiv(shares, vault.totalAssets() + 1, vault.totalSupply() + feeShares + OFFSET_POW, Math.Rounding.Floor);
        uint256 assets = vault.convertToAssets(shares);

        assertEq(assets, expectedAssets, "assets");
        assertGe(assets, assetsBefore, "assets increased");
    }
}
