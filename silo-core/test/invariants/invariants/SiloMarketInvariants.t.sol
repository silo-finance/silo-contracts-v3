// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Ijnterfaces
import {ISilo} from "silo-core/contracts/Silo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import {console} from "forge-std/console.sol";

/// @title SiloMarketInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract SiloMarketInvariants is HandlerAggregator {
    function assert_SILO_INVARIANT_A(address silo) internal {
        try ISilo(silo).accrueInterest() {}
        catch {
            assertTrue(false, SILO_INVARIANT_A);
        }
    }

    function assert_SILO_INVARIANT_D(address user) internal {
        if (_hasDebt(user)) {
            (ISiloConfig.ConfigData memory collateralConfig,) = siloConfig.getConfigsForSolvency(user);

            assertEq(collateralConfig.silo, siloConfig.borrowerCollateralSilo(user), SILO_INVARIANT_D);
        }
    }

    function assert_SILO_INVARIANT_E(address user) internal {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(user);

        if (debtConfig.silo != address(0)) {
            assertFalse(collateralConfig.silo == address(0), SILO_INVARIANT_E);
        }
    }

    function assert_SILO_INVARIANT_F(address user) internal {
        if (IERC20(debtTokens[0]).balanceOf(user) == 0 && IERC20(debtTokens[1]).balanceOf(user) == 0) {
            (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
                siloConfig.getConfigsForSolvency(user);

            assertEq(debtConfig.silo, address(0), SILO_INVARIANT_F);
            assertEq(collateralConfig.silo, address(0), SILO_INVARIANT_F);
        }
    }
}
