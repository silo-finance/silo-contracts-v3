// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {InterestRateModelV2} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

contract InterestRateModelV2Impl is InterestRateModelV2 {
    using SafeCast for int256;

    function mockSetup(address _silo, int256 _ri, int256 _Tcrit) external {
        if (_Tcrit > type(int112).max) revert("[InterestRateModelV2Impl] _Tcrit overflow");
        if (_Tcrit < type(int112).min) revert("[InterestRateModelV2Impl] _Tcrit underflow");

        if (_ri > type(int112).max) revert("[InterestRateModelV2Impl] _ri overflow");
        if (_ri < type(int112).min) revert("[InterestRateModelV2Impl] _ri underflow");

        getSetup[_silo].Tcrit = _Tcrit.toInt112();
        getSetup[_silo].ri = _ri.toInt112();
    }

    function calculateRComp(uint256 _totalDeposits, uint256 _totalBorrowAmount, int256 _x)
        external
        pure
        virtual
        returns (uint256 rcomp, bool overflow)
    {
        return _calculateRComp(_totalDeposits, _totalBorrowAmount, _x);
    }
}
