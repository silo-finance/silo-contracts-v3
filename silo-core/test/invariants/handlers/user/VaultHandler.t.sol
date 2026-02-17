// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {ISilo} from "silo-core/contracts/Silo.sol";

// Libraries
import {console2} from "forge-std/console2.sol";

// Test Contracts
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

    function deposit(uint256 _assets, uint8 i, uint8 j, uint8 k) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(k % 2);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.deposit.selector, _assets, receiver, _collateralType));

        // POST-CONDITIONS

        if (success) {
            _after();

            if (_collateralType == ISilo.CollateralType.Collateral) {
                vault1.getCollateralAndDebtTotalsStorage();
                assertApproxEqAbs(
                    defaultVarsBefore[target].totalAssets + _assets,
                    defaultVarsAfter[target].totalAssets,
                    1,
                    LENDING_HSPOST_A
                );
            }
        }

        if (_assets == 0) {
            assertFalse(success, SILO_HSPOST_B);
        }
    }

    function mint(uint256 _shares, uint8 i, uint8 j, uint8 k) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(k % 2);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.mint.selector, _shares, receiver, _collateralType));

        // POST-CONDITIONS

        if (success) {
            _after();

            if (_collateralType == ISilo.CollateralType.Collateral) {
                assertEq(
                    defaultVarsBefore[target].totalSupply + _shares,
                    defaultVarsAfter[target].totalSupply,
                    LENDING_HSPOST_A
                );
            }
        }

        if (_shares == 0) {
            assertFalse(success, SILO_HSPOST_B);
        }
    }

    function withdraw(uint256 _assets, uint8 i, uint8 j, uint8 k) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(k % 2);

        _before();
        (success, returnData) = actor.proxy(
            target,
            abi.encodeWithSelector(ISilo.withdraw.selector, _assets, receiver, address(actor), _collateralType)
        );

        // POST-CONDITIONS

        if (success) {
            _after();
        }

        if (_assets == 0) {
            assertFalse(success, SILO_HSPOST_B);
        }
    }

    function redeem(uint256 _shares, uint8 i, uint8 j, uint8 k) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(k % 2);

        _before();
        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ISilo.redeem.selector, _shares, receiver, address(actor), _collateralType)
        );

        if (success) {
            _after();
        }

        // POST-CONDITIONS
        if (_shares == 0) {
            assertFalse(success, SILO_HSPOST_B);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          PROPERTIES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_LENDING_INVARIANT_B(uint8 i, uint8 j) public setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        address target = _getRandomSilo(i);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(j % 2);

        uint256 maxWithdraw = ISilo(target).maxWithdraw(address(actor), _collateralType);

        console2.log("maxWithdraw", maxWithdraw);
        console2.log("  liquidity", ISilo(target).getLiquidity());
        console2.log("max redeem", ISilo(target).maxRedeem(address(actor), _collateralType));
        console2.log("type", _collateralType == ISilo.CollateralType.Collateral ? "collateral" : "protected");

        _before();
        (success, returnData) = actor.proxy(
            target,
            abi.encodeWithSelector(
                ISilo.withdraw.selector, maxWithdraw, address(actor), address(actor), _collateralType
            )
        );

        if (success) {
            _after();
        }

        // POST-CONDITIONS

        if (maxWithdraw != 0) {
            assertTrue(success, LENDING_INVARIANT_B);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
