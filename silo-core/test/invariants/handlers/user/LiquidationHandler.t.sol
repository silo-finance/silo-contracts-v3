// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title LiquidationHandler
/// @notice Handler test contract for a set of actions
contract LiquidationHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function liquidationCall(uint256 _debtToCover, bool _receiveSToken, RandomGenerator memory random)
        external
        setupRandomActor(random.i)
    {
        bool success;
        bytes memory returnData;

        address borrower = _getRandomActor(random.i);

        _setTargetActor(borrower);

        // Fuzzing the collateral and debt assets in order to check for edge cases and integraty
        // between the two silos
        address collateralAsset = _getRandomBaseAsset(random.k);
        address debtAsset = _getRandomBaseAsset(random.j);

        _before();
        (success, returnData) = actor.proxy(
            address(liquidationModule),
            abi.encodeWithSelector(
                IPartialLiquidation.liquidationCall.selector,
                collateralAsset,
                debtAsset,
                borrower,
                _debtToCover,
                _receiveSToken
            )
        );

        if (success) {
            _after();
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
