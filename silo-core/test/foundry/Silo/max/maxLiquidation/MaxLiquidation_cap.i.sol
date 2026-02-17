// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MaxLiquidationCommon} from "./MaxLiquidationCommon.sol";

/*
    forge test -vv --ffi --mc MaxLiquidationCapTest

    this tests are for "normal" case,
    where user became insolvent and we can partially liquidate
*/
contract MaxLiquidationCapTest is MaxLiquidationCommon {
    using SiloLensLib for ISilo;

    bool private constant _BAD_DEBT = false;

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxLiquidation_cap
    */
    function test_maxLiquidation_cap() public {
        _createDebtForBorrower(1e18);

        _moveTimeUntilInsolvent();
        _assertBorrowerIsNotSolvent(false);

        (uint256 collateralToLiquidate, uint256 maxDebtToCover, bool sTokenRequired) =
            partialLiquidation.maxLiquidation(borrower);

        emit log_named_uint("         getLiquidity #1", silo0.getLiquidity());
        emit log_named_uint("collateralToLiquidate #1", collateralToLiquidate);

        assertTrue(!sTokenRequired, "sTokenRequired NOT required because it is partial liquidation");

        vm.startPrank(depositor);
        silo0.borrow(silo0.maxBorrow(depositor), depositor, depositor);
        vm.stopPrank();
        emit log_named_uint("getLiquidity after borrow", silo0.getLiquidity());

        (collateralToLiquidate, maxDebtToCover, sTokenRequired) = partialLiquidation.maxLiquidation(borrower);
        assertTrue(sTokenRequired, "sTokenRequired IS required because we borrowed on silo0");

        vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        partialLiquidation.liquidationCall(
            address(token0),
            address(token1),
            borrower,
            maxDebtToCover,
            false // receiveStoken
        );

        _deposit(collateralToLiquidate - silo0.getLiquidity(), address(1));

        (,, sTokenRequired) = partialLiquidation.maxLiquidation(borrower);
        assertTrue(sTokenRequired, "sTokenRequired is still required because of -2");

        _deposit(2, address(1));

        (collateralToLiquidate, maxDebtToCover, sTokenRequired) = partialLiquidation.maxLiquidation(borrower);
        assertTrue(
            !sTokenRequired, "sTokenRequired NOT required because we have 'collateralToLiquidate + 2' in silo0"
        );

        emit log_named_uint("         getLiquidity #2", silo0.getLiquidity());
        emit log_named_uint("collateralToLiquidate #2", collateralToLiquidate);

        partialLiquidation.liquidationCall(
            address(token0),
            address(token1),
            borrower,
            maxDebtToCover,
            false // receiveStoken
        );
    }

    function _withChunks() internal pure virtual override returns (bool) {
        revert("not in use");
    }

    function _executeLiquidation(bool) internal pure override returns (uint256, uint256) {
        // revert("not in use");
        // revert causing warnings about unreachable code in _executeLiquidationAndRunChecks,
        // so we simply returs 1e18,1e18 to avoid warnings and make sure, that if this method wil be fired,
        // test should fail, ebcause there wil be no balance changes
        return (1e18, 1e18);
    }
}
