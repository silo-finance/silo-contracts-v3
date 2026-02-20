// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";

// Invariant Contracts
import {BaseInvariants} from "./BaseInvariants.t.sol";


/// @title Invariants
/// @notice Wrappers for the protocol invariants implemented in each invariants contract
/// @dev recognised by Echidna when property mode is activated
/// @dev Inherits BaseInvariants
abstract contract Invariants is BaseInvariants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     BASE INVARIANTS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

//    function echidna_maxWithdraw_asInputDoesNotRevert() public returns (bool) {
//        return true;
//    }

//    function echidna_BASE_INVARIANT() public returns (bool) {
//        assert_maxWithdraw_asInputDoesNotRevert();
//
//        return true;
//    }
}
