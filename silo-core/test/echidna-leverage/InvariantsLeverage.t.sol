// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {ISilo} from "silo-core/contracts/Silo.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Invariant Contracts
import {Invariants} from "silo-core/test/invariants/Invariants.t.sol";
import {LeverageHandler} from "./handlers/user/LeverageHandler.t.sol";

import {console} from "forge-std/console.sol";

/// @title Invariants
/// @notice Wrappers for the protocol invariants implemented in each invariants contract
/// @dev recognised by Echidna when property mode is activated
/// @dev Inherits BaseInvariants
abstract contract InvariantsLeverage is Invariants, LeverageHandler {
///////////////////////////////////////////////////////////////////////////////////////////////
//                                     BASE INVARIANTS                                       //
///////////////////////////////////////////////////////////////////////////////////////////////

//    function echidna_BORROWING_INVARIANT() public returns (bool) {
//        for (uint256 j = 0; j < actorAddresses.length; j++) {
//            assert_BORROWING_INVARIANT_E(actorAddresses[j]);
//            assert_BORROWING_INVARIANT_D(actorAddresses[j]);
//        }
//        for (uint256 i = 0; i < silos.length; i++) {
//            uint256 sumUserDebtAssets;
//            for (uint256 j = 0; j < actorAddresses.length; j++) {
//                sumUserDebtAssets += ISilo(silos[i]).maxRepay(actorAddresses[j]);
//
//                assert_BORROWING_INVARIANT_A(silos[i], actorAddresses[j]);
//                assert_BORROWING_INVARIANT_G(silos[i], actorAddresses[j]);
//                assert_BORROWING_INVARIANT_H(silos[i], shareTokens[i], actorAddresses[j]);
//            }
//            assert_BORROWING_INVARIANT_B(silos[i], sumUserDebtAssets);
//            assert_BORROWING_INVARIANT_F(silos[i]);
//        }
//
//        return true;
//    }
}
