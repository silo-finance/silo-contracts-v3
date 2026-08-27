// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

// forge test -vv --mc CalculateFractionTest
contract CalculateFractionTest is Test {
    /*
    forge test --mt test_calculateFraction_notReverts_fuzz -vv
    */
    function test_calculateFraction_notReverts_fuzz(uint256 _total, uint256 _percent, uint64 _currentFraction)
        public
        pure
    {
        SiloMathLib.calculateFraction(_total, _percent, _currentFraction);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_calculateFraction_pass -vv
    */
    function test_calculateFraction_pass() public pure {
        _calculateFraction_check({
            _total: 0,
            _percent: 0,
            _currentFraction: 0,
            _integral: 0,
            _fraction: 0,
            _msg: "#1"
        });

        _calculateFraction_check({
            _total: 0,
            _percent: 0.5e18,
            _currentFraction: 0,
            _integral: 0,
            _fraction: 0,
            _msg: "#2"
        });

        _calculateFraction_check({
            _total: 1e18,
            _percent: 0,
            _currentFraction: 1e18,
            _integral: 1,
            _fraction: 0,
            _msg: "#3"
        });

        _calculateFraction_check({
            _total: 111,
            _percent: 0.01e18,
            _currentFraction: 0.5e18,
            _integral: 0,
            _fraction: 0.61e18,
            _msg: "#4" // (111 * 0.01e18 + 0.5e18)  % 1e18
        });

        _calculateFraction_check({
            _total: 123456789,
            _percent: 0.0001e18,
            _currentFraction: 0.55e18,
            _integral: 1,
            _fraction: 228900000000000000,
            _msg: "#5" // (123456789 * 0.0001e18 + 0.55e18)  % 1e18
        });

        _calculateFraction_check({
            _total: 10,
            _percent: 0.1e18,
            _currentFraction: 0,
            _integral: 0,
            _fraction: 0,
            _msg: "#6"
        });

        _calculateFraction_check({
            _total: 100,
            _percent: 0.1e18,
            _currentFraction: 0,
            _integral: 0,
            _fraction: 0,
            _msg: "#7"
        });

        _calculateFraction_check({
            _total: 9,
            _percent: 0.1e18,
            _currentFraction: 0,
            _integral: 0,
            _fraction: 0.9e18,
            _msg: "#8"
        });
    }

    function _calculateFraction_check(
        uint256 _total,
        uint256 _percent,
        uint64 _currentFraction,
        uint256 _integral,
        uint64 _fraction,
        string memory _msg
    ) public pure {
        (uint256 integral, uint64 fraction) = SiloMathLib.calculateFraction(_total, _percent, _currentFraction);

        assertEq(integral, _integral, string.concat(_msg, " integral"));
        assertEq(fraction, _fraction, string.concat(_msg, " fraction"));
    }
}
