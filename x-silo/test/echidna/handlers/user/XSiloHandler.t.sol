// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {XSilo} from "x-silo/contracts/XSilo.sol";
import {IXRedeemPolicy} from "x-silo/contracts/interfaces/IXRedeemPolicy.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title SiloHandler
/// @notice Handler test contract for a set of actions
contract XSiloHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /* 
    
    E.g. num of active pools
    uint256 public activePools;
        
    */

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

//    function redeemSilo(uint256 _xSiloAmountToBurn, uint256 _duration) external setup { TODO
//        bool success;
//        bytes memory returnData;
//
//        _before();
//
//        (success, returnData) = actor.proxy(
//            address(xSilo),
//            abi.encodeWithSelector(IXRedeemPolicy.redeemSilo.selector, _xSiloAmountToBurn, _duration)
//        );
//
//        if (success) {
//            _after();
//        }
//    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           PROPERTIES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

//    function assert_SILO_HSPOST_D() external {
//        bool success;
//
//        _before();
//        ISilo(xSilo).withdrawFees();
//        try ISilo(target).withdrawFees()  {
//            success = true;
//        } catch {
//            success = false;
//        }
//        _after();
//
//        assertFalse(success, SILO_HSPOST_D);
//    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
