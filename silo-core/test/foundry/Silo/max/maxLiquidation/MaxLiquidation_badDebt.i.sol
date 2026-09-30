// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MaxLiquidationTest} from "./MaxLiquidation.i.sol";

/*
    forge test -vv --ffi --mc MaxLiquidationBadDebtTest

    this tests are for "normal" case, when bad debt
    there are no restrictions for input like in other cases, so this file has all scenarios
*/
contract MaxLiquidationBadDebtTest is MaxLiquidationTest {
    bool private constant _BAD_DEBT = true;

    function _maxLiquidation_partial(uint128 _collateral, bool _receiveSToken) internal virtual override {
        _createDebtForBorrower(_collateral);

        vm.warp(block.timestamp + 50 days); // initial time movement to speed up _moveTimeUntilInsolvent

        // for same asset interest increasing slower, because borrower is also depositor, also LT is higher
        _moveTimeUntilBadDebt();

        _assertBorrowerIsNotSolvent(_BAD_DEBT);

        _executeLiquidationAndRunChecks(_receiveSToken);

        _assertBorrowerIsSolvent();
        _ensureBorrowerHasNoDebt();
    }

    function _withChunks() internal pure virtual override returns (bool) {
        return false;
    }
}
