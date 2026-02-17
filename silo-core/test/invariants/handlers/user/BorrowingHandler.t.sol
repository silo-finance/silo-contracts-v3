// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ISilo} from "silo-core/contracts/Silo.sol";

// Libraries
import {console} from "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";
import {TestERC20} from "../../utils/mocks/TestERC20.sol";

/// @title BorrowingHandler
/// @notice Handler test contract for a set of actions
contract BorrowingHandler is BaseHandler {
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

    function borrow(uint256 _assets, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.borrow.selector, _assets, receiver, address(actor)));

        // POST-CONDITIONS

        if (success) {
            _after();

            assertApproxEqAbs(
                defaultVarsBefore[target].debtAssets + _assets,
                defaultVarsAfter[target].debtAssets,
                1,
                BORROWING_HSPOST_M
            );

            assertEq(
                defaultVarsAfter[target].balance + _assets, defaultVarsBefore[target].balance, BORROWING_HSPOST_O
            );
        }
    }

    function borrowShares(uint256 _shares, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        _before();
        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ISilo.borrowShares.selector, _shares, receiver, address(actor))
        );

        if (success) {
            _after();

            assertGe(
                defaultVarsAfter[target].userDebtShares, defaultVarsBefore[target].userDebtShares, BORROWING_HSPOST_Q
            );

            assertGe(defaultVarsAfter[target].userBalance, defaultVarsBefore[target].userBalance, BORROWING_HSPOST_R);
        }
    }

    function repay(uint256 _assets, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address borrower = _getRandomActor(i);

        _setTargetActor(borrower);

        address target = _getRandomSilo(j);

        uint256 maxRepay = ISilo(target).maxRepay(borrower);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(ISilo.repay.selector, _assets, borrower));

        if (success) {
            _after();

            if (_assets >= maxRepay) {
                assertEq(IERC20(_getRandomDebtToken(j)).balanceOf(borrower), 0, BORROWING_HSPOST_B);
            }
            assertLe(defaultVarsAfter[target].userDebt, defaultVarsBefore[target].userDebt, BORROWING_HSPOST_H);
        }
    }

    function repayShares(uint256 _shares, uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address borrower = _getRandomActor(i);

        _setTargetActor(borrower);

        address target = _getRandomSilo(j);

        uint256 maxRepayShares = ISilo(target).maxRepayShares(borrower);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.repayShares.selector, _shares, borrower));

        if (success) {
            _after();

            if (_shares >= maxRepayShares) {
                assertEq(IERC20(_getRandomDebtToken(j)).balanceOf(borrower), 0, BORROWING_HSPOST_B);
            }
            assertLe(defaultVarsAfter[target].userDebt, defaultVarsBefore[target].userDebt, BORROWING_HSPOST_H);
        }
    }

    function transitionCollateral(uint256 _shares, RandomGenerator memory r) external setupRandomActor(r.i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address owner = _getRandomActor(r.i);

        _setTargetActor(owner);

        address target = _getRandomSilo(r.j);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(r.k % 2);

        uint256 liquidity = ISilo(target).getLiquidity();

        _getUserProtectedAssets(target, owner);

        _before();
        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ISilo.transitionCollateral.selector, _shares, owner, _collateralType)
        );

        // POST-CONDITIONS

        if (success) {
            _after();

            uint256 receivedAssets = abi.decode(returnData, (uint256));

            if (_collateralType != ISilo.CollateralType.Protected) {
                assertGe(liquidity, receivedAssets, LENDING_HSPOST_D);
            }
            /* assertApproxEqAbs(
                defaultVarsAfter[target].userAssets, defaultVarsBefore[target].userAssets, 2 wei, BORROWING_HSPOST_J
            ); */
            // TODO remove comment
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          PROPERTIES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_BORROWING_HSPOST_D(uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address borrower = _getRandomActor(i);

        address target = _getRandomSilo(j);

        uint256 maxRepayShares = ISilo(target).maxRepayShares(borrower);

        uint256 debtAmount = ISilo(target).previewRepayShares(maxRepayShares);

        (, address debtAsset) = siloConfig.getDebtShareTokenAndAsset(target);

        if (debtAmount > IERC20(debtAsset).balanceOf(address(actor))) {
            TestERC20(debtAsset).mint(address(actor), debtAmount - IERC20(debtAsset).balanceOf(address(actor)));
        }

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.repayShares.selector, debtAmount, borrower));

        /* if (debtAmount > 0) {
            assertTrue(success, BORROWING_HSPOST_D);
            assertLe(ISilo(target).maxRepay(borrower), 1, BORROWING_HSPOST_D);
        } */

        if (success) {
            _after();
        }
    }

    function assertBORROWING_HSPOST_F(uint8 i, uint8 j) external setupRandomActor(i) {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        uint256 maxBorrow = ISilo(target).maxBorrow(address(actor));

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.borrow.selector, maxBorrow, receiver, address(actor)));

        if (maxBorrow > 0) {
            assertTrue(success, BORROWING_HSPOST_F);
        }

        if (success) {
            _after();
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
