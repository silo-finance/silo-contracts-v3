// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "silo-core/contracts/lib/SiloMathLib.sol";

contract FeeLossFixTest is Test {
    function testFeeLossFix() public {
        uint256 _accruedInterest = 9;
        uint256 _fees = 0.1e18; // 10% fee
        uint256 integralInterest = 1; // max possible
        
        // Exact fee should be 10 * 0.1 = 1.0 -> 1
        // original totalFees calculation
        uint256 _totalFees = (_accruedInterest * _fees) / 1e18; // 9 * 0.1 = 0.9 -> 0
        
        uint256 accruedInterest = _accruedInterest + integralInterest; // 10
        
        uint256 integralRevenue;
        uint64 fraction;
        // remainder = (10 * 0.1e18) % 1e18 = 0
        (integralRevenue, fraction) = SiloMathLib.calculateFraction(accruedInterest, _fees, 0);
        
        // FIX: Re-calculate the integer part of the fee on the FULL accruedInterest
        uint256 totalFeesFixed = (accruedInterest * _fees) / 1e18 + integralRevenue; 
        
        assertEq(totalFeesFixed, 1, "Fee is fixed!");
    }
}
