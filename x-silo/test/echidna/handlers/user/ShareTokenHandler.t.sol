// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title ShareCollateralTokenHandler
/// @notice Handler test contract for a set of actions
contract ShareTokenHandler is BaseHandler {
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

    function approve(uint256 _amount, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address spender = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(xSilo),
            abi.encodeWithSelector(IERC20.approve.selector, spender, _amount)
        );

        if (success) {
            assert(true);
        }
    }

    function transfer(uint256 _amount, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address to = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(xSilo),
            abi.encodeWithSelector(IERC20.transfer.selector, to, _amount)
        );

        if (success) {
            assert(true);
        }

        // POST-CONDITIONS

        if (_amount == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    function transferFrom(uint256 _amount, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address from = _getRandomActor(i);
        // Get one of the three actors randomly
        address to = _getRandomActor(j);

        (success, returnData) = actor.proxy(
            address(xSilo),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                _amount
            )
        );

        if (success) {
            assert(true);
        }

        // POST-CONDITIONS

        if (_amount == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // rescueTokens

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
