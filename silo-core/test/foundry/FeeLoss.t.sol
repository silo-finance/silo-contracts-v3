// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "silo-core/contracts/lib/SiloMathLib.sol";
import "silo-core/contracts/lib/SiloLendingLib.sol";

contract FeeLossTest is Test {
    function testFeeLoss() public {
        uint256 _accruedInterest = 9;
        uint256 _fees = 0.1e18;
        uint256 integralInterest = 2;
        
        uint256 _totalFees = (_accruedInterest * _fees) / 1e18;
        
        uint256 accruedInterest = _accruedInterest + integralInterest;
        
        uint256 integralRevenue;
        uint64 fraction;
        (integralRevenue, fraction) = SiloMathLib.calculateFraction(accruedInterest, _fees, 0);
        
        uint256 totalFees = _totalFees + integralRevenue;
        
        // Exact fee should be 11 * 0.1 = 1.1 -> 1
        assertEq(totalFees, 1, "Fee is lost!");
    }
}
