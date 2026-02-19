// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {Pretty, Strings} from "../utils/Pretty.sol";
import {console} from "forge-std/console.sol";



// Interfaces
import {IERC4626} from "openzeppelin5/token/ERC20/extensions/ERC4626.sol";
import {IVaultHandler} from "../handlers/interfaces/IVaultHandler.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Test Contracts
import {BaseHooks} from "../base/BaseHooks.t.sol";
import {Actor} from "../utils/Actor.sol";

/// @title Default Before After Hooks
/// @notice Helper contract for before and after hooks
/// @dev This contract is inherited by handlers
abstract contract DefaultBeforeAfterHooks is BaseHooks {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using Pretty for bool;

    struct DefaultVars {
        // ERC4626
        uint256 totalSupply;
        uint256 exchangeRate;
        uint256 totalAssets;
        uint256 supplyCap;
        // xSilo
        uint256 balance;
        uint256 cash;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       HOOKS STORAGE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    mapping(address => DefaultVars) defaultVarsBefore;
    mapping(address => DefaultVars) defaultVarsAfter;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           SETUP                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Default hooks setup
    function _setUpDefaultHooks() internal {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HOOKS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _defaultHooksBefore() internal {
        _setXSiloValues(defaultVarsBefore[address(xSilo)]);
    }

    function _defaultHooksAfter() internal {
        _setXSiloValues(defaultVarsAfter[address(xSilo)]);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           SETTERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setXSiloValues(DefaultVars storage _defaultVars) internal {
        _defaultVars.exchangeRate = xSilo.convertToShares(1e18);
        _defaultVars.totalSupply = xSilo.totalSupply();
        _defaultVars.totalAssets = xSilo.totalAssets();
        _defaultVars.balance = IERC20(siloToken).balanceOf(address(xSilo));
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                  GLOBAL POST CONDITIONS                                   //
    /////////////////////////////////////////////////////////////////////////////////////////////*/
}
