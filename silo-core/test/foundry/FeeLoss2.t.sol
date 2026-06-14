// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "silo-core/contracts/lib/SiloMathLib.sol";
import "silo-core/contracts/lib/SiloLendingLib.sol";

contract FeeLoss2Test is Test {
    function testFeeLoss2() public {
        uint256 _accruedInterest = 1000;
        uint256 _fees = 0.5e18; // 50% fee
        uint256 integralInterest = 1;
        
        // Exact fee should be 1001 * 0.5 = 500.5 -> 500
        uint256 _totalFees = (_accruedInterest * _fees) / 1e18; // 1000 * 0.5 = 500
        
        uint256 accruedInterest = _accruedInterest + integralInterest; // 1001
        
        uint256 integralRevenue;
        uint64 fraction;
        // calculateFraction(1001, 0.5e18, 0)
        // remainder = (1001 * 0.5e18) % 1e18 = 500.5e18 % 1e18 = 0.5e18
        // integralRevenue = 0.5e18 / 1e18 = 0
        (integralRevenue, fraction) = SiloMathLib.calculateFraction(accruedInterest, _fees, 0);
        
        uint256 totalFees = _totalFees + integralRevenue; // 500 + 0 = 500
        
        assertEq(totalFees, 500); // 500, but exact is 500!
        assertEq(fraction, 0.5e18); // Wait, fraction is 0.5e18. This is correct!
    }
}
