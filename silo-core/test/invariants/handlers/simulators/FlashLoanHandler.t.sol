// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {ISilo} from "silo-core/contracts/Silo.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title FlashLoanHandler
/// @notice Handler test contract for a set of actions
contract FlashLoanHandler is BaseHandler {
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

    function flashLoan(uint256 _amount, uint256 _amountToRepay, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        address target = _getRandomSilo(i);

        address token = _getRandomBaseAsset(j);

        uint256 maxFlashLoanAmount = ISilo(target).maxFlashLoan(token);

        _amountToRepay = clampBetween(_amountToRepay, 0, type(uint256).max - IERC20(token).totalSupply());

        _before();
        (success, returnData) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IERC3156FlashLender.flashLoan.selector,
                flashLoanReceiver,
                token,
                _amount,
                abi.encode(_amountToRepay, address(actor))
            )
        );

        uint256 flashFee = IERC3156FlashLender(target).flashFee(token, _amount);

        // POST-CONDITIONS

        if ((_amountToRepay >= _amount + flashFee && maxFlashLoanAmount >= _amount) && _amount != 0) {
            assertTrue(success, BORROWING_HSPOST_U1);
        } else {
            assertFalse(success, BORROWING_HSPOST_U2);
        }

        if (success) {
            _after();

            assertEq(
                defaultVarsAfter[target].balance, defaultVarsBefore[target].balance + flashFee, BORROWING_HSPOST_T
            );
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
