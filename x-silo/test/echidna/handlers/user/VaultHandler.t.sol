// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626} from "openzeppelin5/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Libraries
import {console2} from "forge-std/console2.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title VaultHandler
/// @notice Handler test contract for a set of actions
contract VaultHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function deposit(uint256 _assets, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        _beforeCall();

        uint256 balanceBefore = IERC20(siloToken).balanceOf(targetActor);

        (
            success, returnData
        ) = actor.proxy(address(xSilo), abi.encodeWithSelector(IERC4626.deposit.selector, _assets, receiver));

        // POST-CONDITIONS

        if (success) {
            _afterSuccessCall();

            if (defaultVarsBefore[address(xSilo)].totalSupply != 0) {
                assertApproxEqAbs(
                    defaultVarsBefore[address(xSilo)].totalAssets + _assets,
                    defaultVarsAfter[address(xSilo)].totalAssets,
                    1,
                    DEPOSIT_TOTAL_ASSETS
                );
            } else {
                assertEq(defaultVarsBefore[address(xSilo)].totalAssets, 0, TOTAL_ASSETS_AFTER_RESET);

                assertApproxEqAbs(
                    defaultVarsBefore[address(xSilo)].balance + _assets,
                    defaultVarsAfter[address(xSilo)].totalAssets,
                    1,
                    DEPOSIT_TOTAL_ASSETS
                );
            }

            assertLe(_assets, balanceBefore, DEPOSIT_TOO_MUCH);
        } else {
            if (_assets != 0) {
                // TODO I think this assert can fail when _assets generates ZeroShares
                // assertGt(_assets, balanceBefore, DEPOSIT_TOO_MUCH);
            }
        }

        if (_assets == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    function mint(uint256 _shares, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        _beforeCall();

        (success, returnData) =
            actor.proxy(address(xSilo), abi.encodeWithSelector(IERC4626.mint.selector, _shares, receiver));

        // POST-CONDITIONS

        if (success) {
            _afterSuccessCall();

            assertEq(
                defaultVarsBefore[address(xSilo)].totalSupply + _shares,
                defaultVarsAfter[address(xSilo)].totalSupply,
                MINT_TOTAL_SHARES
            );
        }

        if (_shares == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    function withdraw(uint256 _assets, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        _beforeCall();

        (success, returnData) = actor.proxy(
            address(xSilo), abi.encodeWithSelector(IERC4626.withdraw.selector, _assets, receiver, address(actor))
        );

        // POST-CONDITIONS

        if (success) {
            _afterSuccessCall();

            // on withdraw we get max penalty
            // TODO can we make assertion about totalAsset?
//            assertApproxEqAbs(
//                defaultVarsBefore[address(xSilo)].totalAssets - _assets,
//                defaultVarsAfter[address(xSilo)].totalAssets,
//                1,
//                WITHDRAW_TOTAL_ASSETS
//            );
        } else {
            // TODO figure out if below property is true?
            if (_assets != 0) assertGt(_assets, xSilo.maxWithdraw(targetActor), MAX_WITHDRAW_AMOUNT_NOT_REVERT);
        }

        if (_assets == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    function withdrawMax(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        _beforeCall();

        uint256 assets = xSilo.maxWithdraw(targetActor);

        (success, returnData) = actor.proxy(
            address(xSilo), abi.encodeWithSelector(IERC4626.withdraw.selector, assets, targetActor, address(actor))
        );

        if (success) {
            _afterSuccessCall();

            // on withdraw we get max penalty
            if (defaultVarsAfter[address(xSilo)].totalSupply != 0) {
                assertApproxEqAbs(
                    defaultVarsBefore[address(xSilo)].totalAssets - assets,
                    defaultVarsAfter[address(xSilo)].totalAssets,
                    1,
                    WITHDRAW_TOTAL_ASSETS
                );
            } else {
                assertEq(defaultVarsAfter[address(xSilo)].totalAssets, 0, TOTAL_ASSETS_AFTER_RESET);
            }
        } else {
            if (assets != 0) assertTrue(success, MAX_WITHDRAW_AMOUNT_NOT_REVERT);
        }

        if (assets == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    function redeem(uint256 _shares, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        _beforeCall();

        (success, returnData) = actor.proxy(
            address(xSilo), abi.encodeWithSelector(IERC4626.redeem.selector, _shares, receiver, address(actor))
        );

        if (success) {
            _afterSuccessCall();
        }

        // POST-CONDITIONS
        if (_shares == 0) {
            assertFalse(success, MINT_BURN_ZERO_SHARES_IMPOSSIBLE);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          PROPERTIES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

//    function echidna_maxWithdraw_doesNotRevert() public setup returns (bool) {
//
//        xSilo.maxWithdraw(msg.sender);
//        return true;
//    }

//    function assert_maxWithdraw_asInputDoesNotRevert() public setup {
//        bool success;
//        bytes memory returnData;
//
//        uint256 maxWithdraw = xSilo.maxWithdraw(address(actor));
//
//        _beforeCall();
//
//        (success, returnData) = actor.proxy(
//            address(xSilo),
//            abi.encodeWithSelector(
//                xSilo.withdraw.selector, maxWithdraw, address(actor), address(actor)
//            )
//        );
//
//        assertTrue(false); // check if assertion is executed
//
//        if (success) {
//            _afterSuccessCall();
//        }
//
//        // POST-CONDITIONS
//
//        if (maxWithdraw != 0) {
//            assertTrue(success, MAX_WITHDRAW_AS_INPUT);
//        }
//    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
