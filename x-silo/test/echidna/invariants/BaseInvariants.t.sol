// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Ijnterfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Contracts
import {HandlerAggregator} from "../handlers/HandlerAggregator.t.sol";

import {console} from "forge-std/console.sol";

/// @title BaseInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract BaseInvariants is HandlerAggregator {
//    function assert_BASE_INVARIANT_A() internal {
//        uint256 totalAssets = ISilo(silo).totalAssets();
//        uint256 totalSupply = ISilo(silo).totalSupply();
//        assertEq(totalAssets == 0, totalSupply == 0, BASE_INVARIANT_A);
//    }

//    function assert_BASE_INVARIANT_B(address silo, address debtShareToken) internal {
//        uint256 totalAtotalSupplyssets = IERC20(debtShareToken).totalSupply();
//        uint256 totalDebtAssets = ISilo(silo).getDebtAssets();
//        assertEq(totalAtotalSupplyssets == 0, totalDebtAssets == 0, BASE_INVARIANT_B);
//    }
//
//    function assert_BASE_INVARIANT_C(address silo) internal {
//        (uint192 daoAndDeployerFees, uint64 interestRateTimestamp,,,) = ISilo(silo).getSiloStorage();
//        if (interestRateTimestamp == 0) {
//            assertEq(daoAndDeployerFees, 0, BASE_INVARIANT_C);
//        }
//    }
//
//    function assert_BASE_INVARIANT_D(
//        address silo,
//        address debtToken,
//        address collateralToken,
//        address protectedToken,
//        address user
//    ) internal {
//        if (ISilo(silo).isSolvent(user) && IERC20(debtToken).balanceOf(user) > 0) {
//            assertGt(
//                IERC20(collateralToken).balanceOf(user) + IERC20(protectedToken).balanceOf(user), 0, BASE_INVARIANT_D
//            );
//        }
//    }
//
//    function assert_BASE_INVARIANT_E(address silo, address asset) internal {
//        (, uint256 totalProtectedAssets) = ISilo(silo).getCollateralAndProtectedTotalsStorage();
//        uint256 balance = IERC20(asset).balanceOf(silo);
//        assertGe(balance, totalProtectedAssets, BASE_INVARIANT_E);
//    }
//
//    function assert_BASE_INVARIANT_F(address silo, address asset) internal {
//        uint256 liquidity = ISilo(silo).getLiquidity();
//        uint256 balance = IERC20(asset).balanceOf(silo);
//        uint256 protectedAssets = ISilo(silo).getTotalAssetsStorage(ISilo.AssetType.Protected);
//        uint256 daoAndDeployerRevenue = _getDaoAndDeployerFees(silo);
//        uint256 diff;
//        if (balance > protectedAssets + daoAndDeployerRevenue) {
//            diff = balance - protectedAssets - daoAndDeployerRevenue;
//        }
//        assertLe(liquidity, diff, BASE_INVARIANT_F);
//    }
//
//    function assert_BASE_INVARIANT_H() internal {
//        assertFalse(siloConfig.reentrancyGuardEntered(), BASE_INVARIANT_H);
//    }
//
//    function assert_BASE_INVARIANT_J(address silo) internal {
//        ISilo.Fractions memory fractions = ISilo(silo).getFractionsStorage();
//        assertLt(fractions.interest, _PRECISION_DECIMALS, BASE_INVARIANT_J);
//        assertLt(fractions.revenue, _PRECISION_DECIMALS, BASE_INVARIANT_J);
//    }
}
