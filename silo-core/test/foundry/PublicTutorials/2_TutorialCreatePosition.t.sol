// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ISilo, IERC20} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloLens, ISiloLens} from "silo-core/contracts/SiloLens.sol";

/*
    This tutorial will help you to borrow, deposit, repay and withdraw from Silo protocol. 

    $ forge test -vv --ffi --mc TutorialCreatePosition
*/
contract TutorialCreatePosition is Test {
    // wstETH Silo. There are multiple wstETH Silos exist. This and following addresses are examples.
    ISilo public constant SILO0 = ISilo(0x0f3E42679f6Cf6Ee00b7eAC7b1676CA044615402);
    // WETH Silo
    ISilo public constant SILO1 = ISilo(0x58A31D1f2Be10Bf2b48C6eCfFbb27D1f3194e547);
    // wstETH/WETH market config for both Silos
    ISiloConfig public constant SILO_CONFIG = ISiloConfig(0x02ED2727D2Dc29b24E5AC9A7d64f2597CFb74bAB);
    // helper to read the data from Silo protocol
    ISiloLens public SILO_LENS;
    // example user to impersonate deposit
    address public constant EXAMPLE_USER = 0xCeF9Cdd466d03A1cEdf57E014d8F6Bdc87872189;
    address public constant WSTETH = 0x5979D7b546E38E414F7E9822514be443A4800529;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Fork Arbitrum at specific block.
    function setUp() public {
        uint256 blockToFork = 270931754;
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), blockToFork);

        // you can get the latest address from V2 protocol deployments
        SILO_LENS = new SiloLens();

        // get wstETH
        vm.prank(EXAMPLE_USER);
        require(IERC20(WSTETH).transfer(address(this), 100 * 10 ** 18), "transfer failed");
    }

    // Deposit assets to Silo using ERC4626 deposit function.
    function test_deposit() public {
        // 1 wstETH to deposit, SILO0 asset is wstETH.
        uint256 depositAssets = 10 ** 18;
        IERC20(WSTETH).approve(address(SILO0), depositAssets);
        SILO0.deposit(depositAssets, address(this));

        assertTrue(SILO0.balanceOf(address(this)) > 0, "Deposit is successful");
    }

    // Withdraw deposit from Silo using ERC4626 withdraw function.
    function test_withdrawAll() public {
        // create deposit position to withdraw funds from it
        uint256 depositAssets = 10 ** 18;
        _createDepositPosition(depositAssets);
        uint256 balanceBeforeWithdraw = IERC20(WSTETH).balanceOf(address(this));

        // It is better to redeem(shares) instead of withdraw(assets) to withdraw full deposit. Interest rate
        // changes the deposit assets continuously. In the next block the assets will be greater, but the shares
        // will not change. This is critical for UI integrations, but on SC level the assets amount will not change
        // during one transaction.
        uint256 sharesToWithdraw = SILO0.balanceOf(address(this));
        SILO0.redeem(sharesToWithdraw, address(this), address(this));

        uint256 balanceAfterWithdraw = IERC20(WSTETH).balanceOf(address(this));

        assertEq(
            balanceAfterWithdraw - balanceBeforeWithdraw,
            depositAssets - 1,
            "Withdrawal of all assets is successful with 1 wei precision due to rounding"
        );
    }

    // Borrow WETH with wstETH as collateral.
    function test_borrow() public {
        // create deposit position in wstETH Silo to use it as collateral for borrowing in WETH Silo
        _createDepositPosition(10 ** 18);
        assertTrue(SILO0.balanceOf(address(this)) > 0, "Collateral exist in Silo0");

        uint256 borrowAssets = 10 ** 17;
        uint256 balanceBeforeBorrow = IERC20(WETH).balanceOf(address(this));
        SILO1.borrow(borrowAssets, address(this), address(this));
        uint256 balanceAfterBorrow = IERC20(WETH).balanceOf(address(this));

        assertEq(balanceAfterBorrow - balanceBeforeBorrow, borrowAssets, "Borrow is successful, assets received");
    }

    // Repay borrowed WETH with wstETH as collateral
    function test_repayAll() public {
        // create borrow position to repay it later
        uint256 borrowAssets = 10 ** 17;
        _createBorrowPosition(borrowAssets * 10, borrowAssets);

        // It is better to repayShares(shares) instead of repay(assets) to repay full amount of debt. Interest rate
        // changes the repay assets continuously. In the next block the assets will be greater, but the shares
        // will not change. This is critical for UI integrations, but on SC level the assets amount will not change
        // during one transaction.
        uint256 sharesToRepay = SILO1.maxRepayShares(address(this));
        uint256 assetsToApprove = SILO1.previewRepayShares(sharesToRepay);
        IERC20(WETH).approve(address(SILO1), assetsToApprove);
        SILO1.repayShares(sharesToRepay, address(this));

        assertEq(SILO_LENS.getLtv(SILO1, address(this)), 0, "Repay is successful, LTV==0");
    }

    function _createDepositPosition(uint256 _depositAssets) internal {
        IERC20(WSTETH).approve(address(SILO0), _depositAssets);
        SILO0.deposit(_depositAssets, address(this));
    }

    function _createBorrowPosition(uint256 _depositAssets, uint256 _borrowAssets) internal {
        _createDepositPosition(_depositAssets);
        SILO1.borrow(_borrowAssets, address(this), address(this));
    }
}
