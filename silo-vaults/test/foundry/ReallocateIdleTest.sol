// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {MarketAllocation} from "../../contracts/interfaces/ISiloVault.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc ReallocateIdleTest -vvv
*/
contract ReallocateIdleTest is IntegrationTest {
    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();
    }

    function testReallocateSupplyIdle(uint256[3] memory suppliedAssets) public {
        suppliedAssets[0] = bound(suppliedAssets[0], 1, CAP2);
        suppliedAssets[1] = bound(suppliedAssets[1], 1, CAP2);
        suppliedAssets[2] = bound(suppliedAssets[2], 1, CAP2);

        allocations.push(MarketAllocation(idleMarket, 0));
        allocations.push(MarketAllocation(allMarkets[0], suppliedAssets[0]));
        allocations.push(MarketAllocation(allMarkets[1], suppliedAssets[1]));
        allocations.push(MarketAllocation(allMarkets[2], suppliedAssets[2]));
        allocations.push(MarketAllocation(idleMarket, type(uint256).max));

        uint256 idleBefore = _idle();

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(
            allMarkets[0].balanceOf(address(vault)),
            suppliedAssets[0] * SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(0)"
        );
        assertEq(
            allMarkets[1].balanceOf(address(vault)),
            suppliedAssets[1] * SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(1)"
        );
        assertEq(
            allMarkets[2].balanceOf(address(vault)),
            suppliedAssets[2] * SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(2)"
        );

        uint256 expectedIdle = idleBefore - suppliedAssets[0] - suppliedAssets[1] - suppliedAssets[2];
        assertApproxEqAbs(_idle(), expectedIdle, 3, "idle");
    }
}
