// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

contract Assertions is Test {
    using Strings for uint256;

    function assertCloseTo(int256 a, int256 b, int256 delta, string memory err) public {
        int256 diff = a < b ? b - a : a - b;
        if (diff < 0) diff *= -1;

        if (diff > delta) {
            uint256 au = uint256(a < 0 ? -a : a);
            uint256 bu = uint256(b < 0 ? -b : b);
            emit log(string(abi.encodePacked("expect ", au.toString(), " to be close to ", bu.toString())));
        }

        assertLe(diff, delta, err);
    }

    /// @param a tested value
    /// @param b expected value
    /// @param percent how close tested value must be to expected value in % (1e18 == 100%)
    /// @param err message
    function assertRelativeCloseTo(int256 a, int256 b, uint256 percent, string memory err) public {
        uint256 hundredPercent = 1e18;
        int256 diff = a < b ? b - a : a - b;

        uint256 absDiff = uint256(diff < 0 ? -diff : diff);
        uint256 bu = uint256(b < 0 ? -b : b);
        uint256 relativeDiff = absDiff * hundredPercent / bu;

        if (relativeDiff > percent) {
            uint256 au = uint256(a < 0 ? -a : a);
            emit log(string(abi.encodePacked("expect ", au.toString(), " to be close to ", bu.toString())));
            emit log(string(abi.encodePacked("abs difference ", absDiff.toString())));
        }

        assertLe(relativeDiff, percent, err);
    }
}
