// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {OracleNormalization} from "silo-oracles/contracts/lib/OracleNormalization.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --match-path silo-oracles/test/foundry/lib/OracleNormalization.t.sol -vv
*/
contract OracleNormalizationTest is Test {
    /*
    FOUNDRY_PROFILE=oracles forge test -vv --ffi --mt test_calculateNormalizationData_multiplier
    */
    function test_calculateNormalizationData_multiplier() public pure {
        _calculateNormalizationData_multiplier(0, 0);
        _calculateNormalizationData_multiplier(1, 0);
        _calculateNormalizationData_multiplier(0, 1);
        _calculateNormalizationData_multiplier(1, 1);
        _calculateNormalizationData_multiplier(18, 0);
        _calculateNormalizationData_multiplier(0, 18);
    }

    function test_calculateNormalizationData_divider() public pure {
        _calculateNormalizationData_divider(18, 1);
        _calculateNormalizationData_divider(1, 18);
        _calculateNormalizationData_divider(18, 18);
        _calculateNormalizationData_divider(19, 0);
        _calculateNormalizationData_divider(0, 19);
        _calculateNormalizationData_divider(36, 0);
        _calculateNormalizationData_divider(0, 36);
    }
    
    function _calculateNormalizationData_multiplier(uint8 baseDecimals, uint8 priceDecimals) internal pure {
        (uint256 d, uint256 m) = OracleNormalization.calculateNormalizationData({_baseDecimals: baseDecimals, _priceDecimals: priceDecimals});
        assertEq(m, 10 ** (18 - baseDecimals - priceDecimals), "multiplier: not valid");
        assertEq(d, 0, "divider: must be 0 always");
    }
    
    function _calculateNormalizationData_divider(uint8 baseDecimals, uint8 priceDecimals) internal pure {
        (uint256 d, uint256 m) = OracleNormalization.calculateNormalizationData({_baseDecimals: baseDecimals, _priceDecimals: priceDecimals});
        assertEq(d, 10 ** (baseDecimals + priceDecimals - 18), "divider: not valid");
        assertEq(m, 0, "multiplier: must be 0 always");
    }

    function test_calculateNormalizationData_fuzz(uint8 _baseDecimals, uint8 _priceDecimals) public pure {
        vm.assume(_baseDecimals <= 18);
        vm.assume(_priceDecimals <= 18);

        (uint256 d, uint256 m) = OracleNormalization.calculateNormalizationData({_baseDecimals: _baseDecimals, _priceDecimals: _priceDecimals});
        assertEq(_baseDecimals + _priceDecimals + _encodeDecimals(m) - _encodeDecimals(d), 18, "end result must be 18");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test -vv --ffi --mt test_calculateNormalizationData_NormalizationScaleTooLarge
    */
    function test_calculateNormalizationData_NormalizationScaleTooLarge() public {
        vm.expectRevert(OracleNormalization.NormalizationScaleTooLarge.selector);
        OracleNormalization.calculateNormalizationData(19, 18);
        
        vm.expectRevert(OracleNormalization.NormalizationScaleTooLarge.selector);
        OracleNormalization.calculateNormalizationData(37, 0);
    }

    function _encodeDecimals(uint256 _a) internal pure returns (uint8 _decimals) {
        // 10 ** 0 = 1 => 0 decimals
        // 10 ** 1 = 10 => 1 decimals
        while (_a > 1) {
            _a /= 10;
            _decimals++;
        }
    }
}
