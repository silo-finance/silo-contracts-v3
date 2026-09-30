// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {KinkMath} from "../../../../contracts/lib/KinkMath.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc KinkMathLibTest -vv
*/
contract KinkMathLibTest is Test {
    using KinkMath for int256;
    using KinkMath for uint256;

    /*
        FOUNDRY_PROFILE=core_test forge test --mt test_kinkMath_inClosedInterval_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kinkMath_inClosedInterval_fuzz(int256 _var, int256 _low, int256 _hi) public pure {
        vm.assume(_low <= _hi);

        bool result = _var.inClosedInterval(_low, _hi);

        if (_low <= _var && _var <= _hi) assertTrue(result, "var should be between");
        else assertFalse(result, "var should NOT be between");
    }

    /*
        FOUNDRY_PROFILE=core_test forge test --mt test_kinkMath_inOpenIntervalLowIncluded_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kinkMath_inOpenIntervalLowIncluded_fuzz(int256 _var, int256 _low, int256 _hi) public pure {
        vm.assume(_low <= _hi);

        bool result = _var.inOpenIntervalLowIncluded(_low, _hi);

        if (_low <= _var && _var < _hi) assertTrue(result, "var should be in below");
        else assertFalse(result, "var should NOT be in below");
    }

    /*
        FOUNDRY_PROFILE=core_test forge test --mt test_kinkMath_inOpenIntervalTopIncluded_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kinkMath_inOpenIntervalTopIncluded_fuzz(int256 _var, int256 _low, int256 _hi) public pure {
        vm.assume(_low <= _hi);

        bool result = _var.inOpenIntervalTopIncluded(_low, _hi);

        if (_low < _var && _var <= _hi) assertTrue(result, "var should be in above");
        else assertFalse(result, "var should NOT be in above");
    }

    /*
        FOUNDRY_PROFILE=core_test forge test --mt test_kinkMath_inOpenInterval_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kinkMath_inOpenInterval_fuzz(int256 _var, int256 _low, int256 _hi) public pure {
        vm.assume(_low < _hi);

        bool result = _var.inOpenInterval(_low, _hi);

        if (_low < _var && _var < _hi) assertTrue(result, "var should be inside");
        else assertFalse(result, "var should NOT be inside");
    }

    /*
        FOUNDRY_PROFILE=core_test forge test --mt test_kinkMath_wouldOverflowOnCastToInt256_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kinkMath_wouldOverflowOnCastToInt256_fuzz(uint256 _value) public pure {
        bool result = _value.wouldOverflowOnCastToInt256();

        if (_value > uint256(type(int256).max)) assertTrue(result, "value should overflow");
        else assertFalse(result, "value should NOT overflow");
    }
}
