// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {ISilo} from "silo-core/contracts/Silo.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title SiloHandler
/// @notice Handler test contract for a set of actions
contract SiloHandler is BaseHandler {
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

    function accrueInterest(uint8 i) external setupRandomActor(0) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address target = _getRandomSilo(i);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(ISilo.accrueInterest.selector));

        if (success) {
            _after();
        }
    }

    function withdrawFees(uint8 i) external {
        address target = _getRandomSilo(i);

        _before();
        ISilo(target).withdrawFees();

        _after();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           PROPERTIES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_SILO_HSPOST_D(uint8 i) external {
        bool success;
        address target = _getRandomSilo(i);

        _before();
        ISilo(target).withdrawFees();
        try ISilo(target).withdrawFees() {
            success = true;
        } catch {
            success = false;
        }
        _after();

        assertFalse(success, SILO_HSPOST_D);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
