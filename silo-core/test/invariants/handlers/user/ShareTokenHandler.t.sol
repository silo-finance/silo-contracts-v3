// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Contracts
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";

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

    function approve(uint256 _amount, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address spender = _getRandomActor(i);

        address target = _getRandomShareToken(j);

        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.approve.selector, spender, _amount));

        if (success) {
            assert(true);
        }
    }

    function transfer(uint256 _amount, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address to = _getRandomActor(i);

        address target = _getRandomShareToken(j);

        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.transfer.selector, to, _amount));

        if (success) {
            assert(true);
        }

        // POST-CONDITIONS

        if (_amount == 0) {
            assertFalse(success, SILO_HSPOST_B);
        }
    }

    function transferFrom(uint256 _amount, uint8 i, uint8 j, uint8 k) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address from = _getRandomActor(i);
        // Get one of the three actors randomly
        address to = _getRandomActor(j);

        address target = _getRandomShareToken(k);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, _amount));

        if (success) {
            assert(true);
        }

        // POST-CONDITIONS

        if (_amount == 0) {
            assertFalse(success, SILO_HSPOST_B);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       DEBT TOKEN ACTIONS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setReceiveApproval(uint256 _amount, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address owner = _getRandomActor(i);

        address target = _getRandomDebtToken(j);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ShareDebtToken.setReceiveApproval.selector, owner, _amount));

        if (success) {
            assert(true);
        }
    }

    function decreaseReceiveAllowance(uint256 _subtractedValue, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address owner = _getRandomActor(i);

        address target = _getRandomDebtToken(j);

        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ShareDebtToken.decreaseReceiveAllowance.selector, owner, _subtractedValue)
        );

        if (success) {
            assert(true);
        }
    }

    function increaseReceiveAllowance(uint256 _addedValue, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address owner = _getRandomActor(i);

        address target = _getRandomDebtToken(j);

        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ShareDebtToken.increaseReceiveAllowance.selector, owner, _addedValue)
        );

        if (success) {
            assert(true);
        }
    }

    function receiveAllowance(uint256, /* _addedValue */ uint8 i, uint8 j, uint8 k) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address owner = _getRandomActor(i);

        address recipient = _getRandomActor(j);

        address target = _getRandomDebtToken(k);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ShareDebtToken.receiveAllowance.selector, owner, recipient));

        if (success) {
            assert(true);
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
