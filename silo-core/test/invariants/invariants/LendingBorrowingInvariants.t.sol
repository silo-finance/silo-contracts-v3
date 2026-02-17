// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Ijnterfaces
import {ISilo} from "silo-core/contracts/Silo.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Libraries
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import {console} from "forge-std/console.sol";

/// @title LendingBorrowingInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract LendingBorrowingInvariants is HandlerAggregator {
    using SiloLensLib for ISilo;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          LENDING                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    function assert_LENDING_INVARIANT_A(address silo, address user) internal {
        uint256 maxWithdrawal = _maxWithdraw(silo, user);
        uint256 liquidity = ISilo(silo).getLiquidity();

        assertLe(maxWithdrawal, liquidity, LENDING_INVARIANT_A);
    }

    function assert_LENDING_INVARIANT_C(address silo, address user) internal {
        if (siloConfig.getDebtSilo(user) == address(0)) {
            uint256 shares = IERC20(silo).balanceOf(user);
            uint256 balance = ISilo(silo).convertToAssets(shares);
            uint256 liquidity = ISilo(silo).getLiquidity();
            if (liquidity >= balance && liquidity > 1) {
                assertEq(_maxRedeem(silo, user), shares, LENDING_INVARIANT_C);
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        BORROWING                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_BORROWING_INVARIANT_A(address silo, address user) internal {
        uint256 totalDebtAssets = ISilo(silo).getDebtAssets();
        uint256 userDebt = ISilo(silo).maxRepay(user);

        assertGe(totalDebtAssets, userDebt, BORROWING_INVARIANT_A);
    }

    function assert_BORROWING_INVARIANT_B(address silo, uint256 sumUserDebt) internal {
        uint256 debtAssets = ISilo(silo).getDebtAssets();

        assertApproxEqAbs(debtAssets, sumUserDebt, NUMBER_OF_ACTORS, BORROWING_INVARIANT_B);
    }

    function assert_BORROWING_INVARIANT_D(address user) internal {
        address debtSilo = siloConfig.getDebtSilo(user);

        if (debtSilo == address(0)) return;

        (address debtShareToken,) = siloConfig.getDebtShareTokenAndAsset(debtSilo);

        if (IERC20(debtShareToken).balanceOf(user) != 0) {
            address collateralSilo = siloConfig.borrowerCollateralSilo(user);
            (address shareToken,) =
                siloConfig.getCollateralShareTokenAndAsset(collateralSilo, ISilo.CollateralType.Protected);

            uint256 collateralBalance = IERC20(collateralSilo).balanceOf(user) + IERC20(shareToken).balanceOf(user);
            assertGt(collateralBalance, 0, BORROWING_INVARIANT_D);
        }
    }

    function assert_BORROWING_INVARIANT_E(address user) internal {
        uint256 debtSilo0 = IERC20(debtTokens[0]).balanceOf(user);
        uint256 debtSilo1 = IERC20(debtTokens[1]).balanceOf(user);

        if (debtSilo0 != 0) {
            assertEq(debtSilo1, 0, BORROWING_INVARIANT_E);
        } else if (debtSilo1 != 0) {
            assertEq(debtSilo0, 0, BORROWING_INVARIANT_E);
        }
    }

    function assert_BORROWING_INVARIANT_F(address silo) internal {
        uint256 totalSupply = IERC20(silo).totalSupply();

        if (totalSupply != 0) {
            assertGt(ISilo(silo).totalAssets(), 0, BORROWING_INVARIANT_F);
        }
    }

    function assert_BORROWING_INVARIANT_G(address silo, address user) internal {
        uint256 debtSilo0 = IERC20(debtTokens[0]).balanceOf(user);
        uint256 debtSilo1 = IERC20(debtTokens[1]).balanceOf(user);

        if (debtSilo0 == 0 && debtSilo1 == 0) {
            assertTrue(ISilo(silo).isSolvent(user), BORROWING_INVARIANT_G);
            assertEq(ISilo(silo).getLtv(user), 0, BORROWING_INVARIANT_G);
        }
    }

    function assert_BORROWING_INVARIANT_H(address silo, address collateralShareToken, address user) internal {
        uint256 maxRedeem = _maxRedeem(silo, user);
        uint256 balance = IERC20(collateralShareToken).balanceOf(user);

        assertLe(maxRedeem, balance, BORROWING_INVARIANT_H);
    }
}
