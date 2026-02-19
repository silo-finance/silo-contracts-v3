// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";

import {ErrorsLib} from "../../contracts/libraries/ErrorsLib.sol";
import {EventsLib} from "../../contracts/libraries/EventsLib.sol";
import {MarketConfig} from "../../contracts/libraries/PendingLib.sol";
import {IntegrationTest} from "./helpers/IntegrationTest.sol";
import {CAP, MIN_TEST_ASSETS, MAX_TEST_ASSETS, TIMELOCK} from "./helpers/BaseTest.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc ERC4626Test -vvv
*/
contract ERC4626Test is IntegrationTest, IERC3156FlashBorrower {
    uint256 public vaultDecimalsOffset;

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();

        vaultDecimalsOffset = vault.DECIMALS_OFFSET();
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testDecimals -vvv
    */
    function testDecimals(uint8 decimals) public {
        vm.assume(decimals <= 18);
        vm.mockCall(address(loanToken), abi.encodeWithSignature("decimals()"), abi.encode(decimals));

        vault = createSiloVault(OWNER, TIMELOCK, address(loanToken), "SiloVault Vault", "MMV");

        assertEq(vault.decimals(), decimals, "offset does not affect decimals");
        assertEq(vault.DECIMALS_OFFSET(), 6, "DECIMALS_OFFSET");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testMint -vvv
    */
    function testMint(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 shares = vault.convertToShares(assets);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 deposited = vault.mint(shares, ONBEHALF);

        assertGt(deposited, 0, "deposited");
        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault) 0, it was deposited to market");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), assets, "expectedSupplyAssets(vault)");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testDeposit -vvv
    */
    function testDeposit(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), assets, "expectedSupplyAssets(vault)");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeem -vvv
    */
    function testRedeem(uint256 deposited, uint256 redeemed) public {
        // (uint256 deposited, uint256 redeemed) = (5274, 1000000);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        redeemed = bound(redeemed, 1, shares);

        vm.assume(vault.convertToAssets(redeemed - 1) != 0);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() - vault.convertToAssets(redeemed - 1));
        vm.prank(ONBEHALF);
        vault.redeem(redeemed - 1, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares - redeemed + 1, "balanceOf(ONBEHALF)");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdraw -vvv
    */
    function testWithdraw(uint256 deposited, uint256 withdrawn) public {
        vm.assume(deposited > 1);
        vm.assume(withdrawn > 1);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 1, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() - withdrawn + 1);
        vm.prank(ONBEHALF);
        uint256 redeemed = vault.withdraw(withdrawn - 1, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawMarketBalanceTracker -vvv
    */
    function testWithdrawMarketBalanceTracker() public {
        IERC4626 market0 = vault.withdrawQueue(0);
        IERC4626 market1 = vault.withdrawQueue(1);

        MarketConfig memory config1 = vault.config(market1);

        uint256 depositOverCap = 100;

        uint256 depositAmount = config1.cap + depositOverCap;

        vm.prank(SUPPLIER);
        vault.deposit(depositAmount, ONBEHALF);

        uint256 balanceBefore0 = vault.balanceTracker(market0);
        uint256 balanceBefore1 = vault.balanceTracker(market1);

        assertEq(balanceBefore0, depositOverCap, "balanceBefore0");
        assertEq(balanceBefore1, config1.cap, "balanceBefore1");

        uint256 withdrawOverCap = 300;

        uint256 withdrawAmount = depositOverCap + withdrawOverCap;

        vm.prank(ONBEHALF);
        vault.withdraw(withdrawAmount, RECEIVER, ONBEHALF);

        uint256 balanceAfter0 = vault.balanceTracker(market0);
        uint256 balanceAfter1 = vault.balanceTracker(market1);

        assertEq(balanceAfter0, 0, "balanceAfter0");
        assertEq(balanceAfter1, config1.cap - withdrawOverCap, "balanceAfter1");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawFailedToWithdraw -vvv
    */
    function testWithdrawFailedToWithdraw() public {
        IERC4626 market = vault.withdrawQueue(0);
        MarketConfig memory config = vault.config(market);

        vm.prank(SUPPLIER);
        vault.deposit(config.cap, ONBEHALF);

        uint256 balanceBefore = market.balanceOf(address(vault));
        uint256 maxAssetsToWithdraw = market.previewRedeem(balanceBefore);
        uint256 assets = maxAssetsToWithdraw / 2;

        bytes memory data = abi.encodeWithSelector(IERC4626.withdraw.selector, assets, address(vault), address(vault));

        vm.mockCall(address(market), data, abi.encode(maxAssetsToWithdraw)); // report wrong amount
        vm.expectCall(address(market), data);

        vm.prank(ONBEHALF);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.FailedToWithdraw.selector));
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawIdle -vvv
    */
    function testWithdrawIdle(uint256 deposited, uint256 withdrawn) public {
        vm.assume(deposited != 0);
        vm.assume(withdrawn != 0);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 0, deposited);

        _setCap(allMarkets[0], 0);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() - withdrawn);
        vm.prank(ONBEHALF);
        uint256 redeemed = vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
        assertEq(_idle(), deposited - withdrawn, "idle");
    }

    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeemTooMuch -vvv
    */
    function testRedeemTooMuch(uint256 deposited) public {
        vm.assume(deposited != 0);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.startPrank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, SUPPLIER);
        vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        vm.prank(SUPPLIER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SUPPLIER, shares, shares + 1)
        );
        vault.redeem(shares + 1, RECEIVER, SUPPLIER);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawAll -vvv
    */
    function testWithdrawAll(uint256 assets) public {
        vm.assume(assets != 0);

        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(assets, ONBEHALF);

        assertEq(vault.maxWithdraw(ONBEHALF), assets - 1, "maxWithdraw(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 shares = vault.withdraw(assets - 1, RECEIVER, ONBEHALF);

        uint256 mintedRoundedDown = minted - 10 ** vaultDecimalsOffset;

        assertEq(shares, mintedRoundedDown, "shares");
        assertEq(vault.balanceOf(ONBEHALF), 10 ** vaultDecimalsOffset, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), assets - 1, "loanToken.balanceOf(RECEIVER)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), 1, "expectedSupplyAssets(vault)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeemAll -vvv
    */
    function testRedeemAll(uint256 deposited) public {
        vm.assume(deposited != 0);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, ONBEHALF);

        // because of the underestimation in the Silo
        uint256 expectedMaxRedeem = minted - 10 ** vaultDecimalsOffset;

        assertEq(vault.maxRedeem(ONBEHALF), expectedMaxRedeem, "maxRedeem(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 assets = vault.redeem(expectedMaxRedeem, RECEIVER, ONBEHALF);

        assertEq(assets, deposited - 1, "assets");
        assertEq(vault.balanceOf(ONBEHALF), 10 ** vaultDecimalsOffset, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), deposited - 1, "loanToken.balanceOf(RECEIVER)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), 1, "expectedSupplyAssets(vault)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeemAllWith1WeiDeposit -vvv
    */
    function testRedeemAllWith1WeiDeposit(uint256 deposited) public {
        vm.assume(deposited != 0);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, ONBEHALF);

        assertEq(vault.maxRedeem(ONBEHALF), minted - 10 ** vaultDecimalsOffset, "maxRedeem(ONBEHALF)");

        vm.prank(ONBEHALF);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.NotEnoughLiquidity.selector));
        vault.redeem(minted, RECEIVER, ONBEHALF);

        vm.prank(SUPPLIER);
        vault.deposit(1, SUPPLIER);

        // 1 wei solves the issue created by the liquidity underestimation in the Silo maxWithdraw fn
        assertEq(vault.maxRedeem(ONBEHALF), minted, "maxRedeem(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 assets = vault.redeem(minted, RECEIVER, ONBEHALF);

        assertEq(assets, deposited, "assets");
        assertEq(vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), deposited, "loanToken.balanceOf(RECEIVER)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeemNotDeposited -vvv
    */
    function testRedeemNotDeposited(uint256 deposited) public {
        vm.assume(deposited != 0);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        uint256 sharesRoundedDown = shares - 10 ** vaultDecimalsOffset;

        vm.prank(SUPPLIER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SUPPLIER, 0, sharesRoundedDown)
        );

        vault.redeem(sharesRoundedDown, SUPPLIER, SUPPLIER);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testRedeemNotApproved -vvv
    */
    function testRedeemNotApproved(uint256 deposited) public {
        vm.assume(deposited != 0);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        uint256 sharesRoundedDown = shares - 10 ** vaultDecimalsOffset;

        vm.prank(RECEIVER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, RECEIVER, 0, sharesRoundedDown)
        );

        vault.redeem(sharesRoundedDown, RECEIVER, ONBEHALF);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawNotApproved -vvv
    */
    function testWithdrawNotApproved(uint256 assets) public {
        vm.assume(assets != 0);

        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 shares = vault.previewWithdraw(assets);

        uint256 sharesRoundedDown = shares - 10 ** vaultDecimalsOffset;

        vm.prank(RECEIVER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, RECEIVER, 0, sharesRoundedDown)
        );

        vault.withdraw(assets - 1, RECEIVER, ONBEHALF);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testTransferFrom -vvv
    */
    function testTransferFrom(uint256 deposited, uint256 toTransfer) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        toTransfer = bound(toTransfer, 0, shares);

        vm.prank(ONBEHALF);
        vault.approve(SUPPLIER, toTransfer);

        vm.prank(SUPPLIER);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        vault.transferFrom(ONBEHALF, RECEIVER, toTransfer);

        assertEq(vault.balanceOf(ONBEHALF), shares - toTransfer, "balanceOf(ONBEHALF)");
        assertEq(vault.balanceOf(RECEIVER), toTransfer, "balanceOf(RECEIVER)");
        assertEq(vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testTransferFromNotApproved -vvv
    */
    function testTransferFromNotApproved(uint256 deposited, uint256 amount) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        amount = bound(amount, 0, shares);

        vm.prank(SUPPLIER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SUPPLIER, 0, shares));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        vault.transferFrom(ONBEHALF, RECEIVER, shares);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawMoreThanBalanceButLessThanTotalAssets -vvv
    */
    function testWithdrawMoreThanBalanceButLessThanTotalAssets(uint256 deposited, uint256 assets) public {
        vm.assume(deposited > 1);
        vm.assume(assets > 1);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.startPrank(SUPPLIER);
        uint256 shares = vault.deposit(deposited / 2, ONBEHALF);
        vault.deposit(deposited / 2, SUPPLIER);
        vm.stopPrank();

        assets = bound(assets, deposited / 2 + 1, vault.totalAssets());

        uint256 sharesBurnt = vault.previewWithdraw(assets);

        uint256 expectedSharesBurnt = sharesBurnt - 10 ** vaultDecimalsOffset;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, ONBEHALF, shares, expectedSharesBurnt
            )
        );

        vm.prank(ONBEHALF);
        vault.withdraw(assets - 1, RECEIVER, ONBEHALF);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawMoreThanTotalAssets -vvv
    */
    function testWithdrawMoreThanTotalAssets(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assets = bound(assets, deposited + 1, type(uint256).max / (deposited + 1));

        vm.prank(ONBEHALF);
        vm.expectRevert(ErrorsLib.NotEnoughLiquidity.selector);
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testWithdrawMoreThanBalanceAndLiquidity -vvv
    */
    function testWithdrawMoreThanBalanceAndLiquidity(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assets = bound(assets, deposited + 1, type(uint256).max / (deposited + 1));

        // Borrow liquidity.
        vm.startPrank(BORROWER);
        silo0.deposit(type(uint128).max, BORROWER);
        silo1.borrow(1, BORROWER, BORROWER);

        vm.startPrank(ONBEHALF);
        vm.expectRevert(ErrorsLib.NotEnoughLiquidity.selector);
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testTransfer -vvv
    */
    function testTransfer(uint256 deposited, uint256 toTransfer) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, ONBEHALF);

        toTransfer = bound(toTransfer, 0, minted);

        vm.prank(ONBEHALF);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        vault.transfer(RECEIVER, toTransfer);

        assertEq(vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
        assertEq(vault.balanceOf(ONBEHALF), minted - toTransfer, "balanceOf(ONBEHALF)");
        assertEq(vault.balanceOf(RECEIVER), toTransfer, "balanceOf(RECEIVER)");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testMaxWithdraw -vvv
    */
    function testMaxWithdraw(uint256 depositedAssets, uint256 borrowedAssets) public {
        depositedAssets = bound(depositedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        borrowedAssets = bound(borrowedAssets, MIN_TEST_ASSETS, depositedAssets);

        vm.prank(SUPPLIER);
        vault.deposit(depositedAssets, ONBEHALF);

        vm.startPrank(BORROWER);
        silo0.deposit(type(uint128).max, BORROWER);
        silo1.borrow(borrowedAssets, BORROWER, BORROWER);

        uint256 expectedMaxWithdraw = depositedAssets - borrowedAssets;
        // -1 because of the rounding down in the maxWithdraw function
        if (expectedMaxWithdraw != 0) expectedMaxWithdraw--;

        assertLe(
            expectedMaxWithdraw - vault.maxWithdraw(ONBEHALF),
            1,
            "maxWithdraw(ONBEHALF) can be off by 1 wei becaose of fractions"
        );
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testMaxWithdrawFlashLoan -vvv
    */
    function testMaxWithdrawFlashLoan(uint256 supplied, uint256 deposited) public {
        supplied = bound(supplied, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        vm.prank(SUPPLIER);
        silo1.deposit(supplied, ONBEHALF);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assertLe(deposited - vault.maxWithdraw(ONBEHALF), 1, "maxWithdraw allow to be off by 1 wei");
        assertEq(loanToken.balanceOf(address(silo1)), supplied + deposited, "balanceOf");

        silo1.flashLoan(
            IERC3156FlashBorrower(address(this)), address(loanToken), loanToken.balanceOf(address(silo1)), ""
        );
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testMaxDeposit -vvv
    */
    function testMaxDeposit() public {
        uint256 cap = 1 ether;

        _setCap(allMarkets[0], cap);

        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        vm.prank(SUPPLIER);
        allMarkets[0].deposit(1 ether, SUPPLIER);

        vm.startPrank(BORROWER);
        silo0.deposit(2 ether, BORROWER);
        silo1.borrow(1 ether, BORROWER, BORROWER);
        vm.stopPrank();

        _forward(1_000);

        uint256 vaultDepositAmount = 0.65 ether;

        vm.prank(SUPPLIER);
        vault.deposit(vaultDepositAmount, ONBEHALF);

        assertEq(
            vault.maxDeposit(address(0)), cap - vaultDepositAmount, "maxDeposit should be cap - vaultDepositAmount"
        );
    }

    function onFlashLoan(address, address, uint256, uint256, bytes calldata) external view returns (bytes32) {
        // this is where silo implementation differs, on silo flashloan state of silo does not change
        // so liquidity stays the same (however not correct during flashloan)
        // -1 because of the underestimation in maxWithdraw function
        assertGe(vault.maxWithdraw(ONBEHALF), MIN_TEST_ASSETS - 1, "onFlashLoan assertion MIN_TEST_ASSETS");
        assertLe(vault.maxWithdraw(ONBEHALF), MAX_TEST_ASSETS, "onFlashLoan assertion MAX_TEST_ASSETS");

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
