// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title SiloConfigHandler
/// @notice Handler test contract for a set of actions
contract SiloConfigHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function accrueInterestForSilo(uint8 i) external {
        address silo = _getRandomSilo(i);

        _before();
        siloConfig.accrueInterestForSilo(silo);
        _after();

        // POST-CONDITIONS

        if (defaultVarsBefore[silo].debtAssets > 1) {
            // We account for fractions delta
            assertGe(defaultVarsAfter[silo].debtAssets, defaultVarsBefore[silo].debtAssets - 2, SILO_HSPOST_A);
        }

        if (defaultVarsBefore[silo].collateralAssets > 1) {
            // We account for fractions delta
            assertGe(
                defaultVarsAfter[silo].collateralAssets, defaultVarsBefore[silo].collateralAssets - 2, SILO_HSPOST_A
            );
        }
    }

    function accrueInterestForBothSilos() external {
        _before();
        siloConfig.accrueInterestForBothSilos();
        _after();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
