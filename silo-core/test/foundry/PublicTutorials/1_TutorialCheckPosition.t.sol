// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLens, ISiloLens} from "silo-core/contracts/SiloLens.sol";

/*
    This tutorial will help you to read any borrow/deposit position data from Silo protocol. 
    Deposited assets, borrowed assets, interest rates and more.

    $ forge test -vv --ffi --mc TutorialCheckPosition
*/
contract TutorialCheckPosition is Test {
    // wstETH Silo. There are multiple wstETH Silos exist. This and following addresses are examples.
    ISilo public constant SILO0 = ISilo(0x0f3E42679f6Cf6Ee00b7eAC7b1676CA044615402);
    // WETH Silo
    ISilo public constant SILO1 = ISilo(0x58A31D1f2Be10Bf2b48C6eCfFbb27D1f3194e547);
    // wstETH/WETH market config for both Silos
    ISiloConfig public constant SILO_CONFIG = ISiloConfig(0x02ED2727D2Dc29b24E5AC9A7d64f2597CFb74bAB);
    // helper to read the data from Silo protocol
    ISiloLens public SILO_LENS;
    // example user address
    address public constant EXAMPLE_USER = 0x6d228Fa4daD2163056A48Fc2186d716f5c65E89A;

    // Fork Arbitrum at specific block.
    function setUp() public {
        uint256 blockToFork = 270931754;
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), blockToFork);

        // you can get the latest address from V2 protocol deployments
        SILO_LENS = new SiloLens();
    }

    // Get an amount of user's deposited assets. ERC4626 shares represent regular deposits, which can be borrowed by
    // other users and generate interest.
    function test_getMyRegularDepositAmount() public view {
        uint256 userShares = SILO1.balanceOf(EXAMPLE_USER);
        uint256 userAssets = SILO1.previewRedeem(userShares);

        assertEq(userAssets, 2 * 10 ** 16, "User has 0.02 WETH deposited in the lending market");
    }

    // Get deposit APR. 10**18 current interest rate is equal to 100%/year.
    function test_getDepositAPR() public view {
        uint256 currentDepositInterestRate = SILO_LENS.getDepositAPR(SILO0);

        assertEq(currentDepositInterestRate, 119948832360394647, "Current deposit interest rate is ~11.99% / year");
    }

    // Any lending protocol does not guarantee the ability to withdraw the borrowable deposit at any time, because
    // it can be borrowed by another user. That is why Silo has a protected deposits feature. Any borrower can
    // deposit in protected mode to make the deposit unborrowable by other users. Deposited funds will be used
    // only as collateral and not generate any interest. The advantage of protected deposit is an opportunity to
    // withdraw it any time.
    function test_getMyProtectedDepositsAmount() public view {
        (address protectedShareToken,,) = SILO_CONFIG.getShareTokens(address(SILO1));
        uint256 userProtectedShares = IShareToken(protectedShareToken).balanceOf(EXAMPLE_USER);
        uint256 userProtectedAssets = SILO1.previewRedeem(userProtectedShares, ISilo.CollateralType.Protected);

        assertEq(userProtectedAssets, 12345 * 10 ** 11, "User has 0.0012345 WETH protected deposit");
    }

    // SiloLens contracts can be used to get the total of regular + protected deposits per user.
    function test_getMyAllDepositsAmount() public view {
        uint256 userRegularAndProtectedAssets = SILO_LENS.collateralBalanceOfUnderlying(SILO1, EXAMPLE_USER);

        assertEq(
            userRegularAndProtectedAssets,
            212345 * 10 ** 11,
            "User has ~0.0212345 WETH in regular and protected deposits"
        );
    }

    // Example user deposits ETH collateral in silo1 and borrows wstETH in silo0. User's debt grows continuously by
    // interest rate. In the example we will calculate user's borrowed amount as an amount the user have to repay.
    function test_getMyBorrowedAmount() public view {
        uint256 userBorrowedAmount = SILO_LENS.debtBalanceOfUnderlying(SILO0, EXAMPLE_USER);

        assertEq(userBorrowedAmount, 10402425735829051, "User have to repay ~0.0104 wstETH including interest");
        assertEq(userBorrowedAmount, SILO0.maxRepay(EXAMPLE_USER), "Same way to read the debt amount");
    }

    // Get borrow APR. 10**18 current interest rate is equal to 100%/year.
    function test_getBorrowAPR() public view {
        uint256 currentBorrowInterestRate = SILO_LENS.getBorrowAPR(SILO0);

        assertEq(currentBorrowInterestRate, 141827957285328000, "Current debt interest rate is ~14.18% / year");
    }

    // Get user's loan-to-value ratio. For example, 0.5 * 10**18 LTV is for a position with 10$ collateral and
    // 5$ borrowed assets.
    function test_getMyLTV() public view {
        uint256 userLTVSilo0 = SILO_LENS.getLtv(SILO0, EXAMPLE_USER);
        uint256 userLTVSilo1 = SILO_LENS.getLtv(SILO1, EXAMPLE_USER);

        assertEq(userLTVSilo0, 579636700972035697, "User loan-to-value ratio is ~58%");
        assertEq(userLTVSilo0, userLTVSilo1, "User loan-to-value ratio is consistent for both silos in SiloConfig");
    }

    // Check if the user is solvent. If the user is insolvent, borrow position can be liquidated.
    function test_getMySolvency() public view {
        bool isSolventSilo0 = SILO0.isSolvent(EXAMPLE_USER);
        bool isSolventSilo1 = SILO1.isSolvent(EXAMPLE_USER);

        assertTrue(isSolventSilo0, "User is solvent");
        assertEq(isSolventSilo0, isSolventSilo1, "Solvency is consistent for both silos in SiloConfig");
    }
}
