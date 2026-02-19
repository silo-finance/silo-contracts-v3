// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

contract MulDivOverflow {
    function mulDiv(uint256 _a, uint256 _b, uint256 _c) external pure {
        _a * _b / _c;
    }
}

/*
    forge test -vv --mc MulDivOverflowTest
*/
contract MulDivOverflowTest is Test {
    MulDivOverflow immutable MUL_DIV_OVERFLOW;

    constructor() {
        MUL_DIV_OVERFLOW = new MulDivOverflow();
    }

    /*
    forge test -vv --mt test_mulOverflow_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_mulOverflow_fuzz(uint256 _a, uint256 _b, uint256 _c) public view {
        vm.assume(_c != 0);

            SiloMathLib.mulDivOverflow(_a, _b, _c);
        try MUL_DIV_OVERFLOW.mulDiv(_a, _b, _c) {
            assertTrue(true, "no overflow");
        } catch {
            assertEq(SiloMathLib.mulDivOverflow(_a, _b, _c), 0, "0 on overflow");
        }
    }
}
