// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";

contract KinkInternalMock is DynamicKinkModel {
    function calculateUtiliation(uint256 _collateralAssets, uint256 _debtAssets) external pure returns (int256) {
        return super._calculateUtiliation(_collateralAssets, _debtAssets);
    }

    function capK(int256 _k, int256 _kmin, int256 _kmax) external pure returns (int96) {
        return super._capK(_k, _kmin, _kmax);
    }
}

/*
FOUNDRY_PROFILE=core_test forge test --mc KinkModalInternalTest -vv
*/
contract KinkModalInternalTest is Test {
    int256 constant _DP = 1e18;
    KinkInternalMock irm = new KinkInternalMock();

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_calculateUtiliation -vv
    */
    function test_kink_calculateUtiliation_zeros() public view {
        assertEq(irm.calculateUtiliation(0, 0), 0, "expect all zeros");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_calculateUtiliation_pass -vv
    */
    function test_kink_calculateUtiliation_pass() public view {
        assertEq(irm.calculateUtiliation({_collateralAssets: 1e18, _debtAssets: 0}), 0, "no debt, no utilization");
        // no collateral, no utilization - this is logic from SiloMathLib
        // assertEq(irm.calculateUtiliation({_collateralAssets: 0, _debtAssets: 1}), _DP, "if only debt, utilization is 100%");
        assertEq(
            irm.calculateUtiliation({_collateralAssets: 1, _debtAssets: 2}), _DP, "if bad debt, utilization is 100%"
        );

        assertEq(irm.calculateUtiliation({_collateralAssets: 1e18, _debtAssets: 1e18}), _DP, "1/1");
        assertEq(irm.calculateUtiliation({_collateralAssets: 1e18, _debtAssets: 0.5e18}), _DP / 2, "1/2");
        assertEq(irm.calculateUtiliation({_collateralAssets: 100, _debtAssets: 33}), 0.33e18, "1/3");
        assertEq(irm.calculateUtiliation({_collateralAssets: 1e18, _debtAssets: 33}), 33, "33");
        assertEq(
            irm.calculateUtiliation({_collateralAssets: 1e18 - 2, _debtAssets: 333333333333333333}),
            333333333333333333,
            "3(3) rounding up"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_calculateUtiliation_neverRevert_neverOverDP_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kink_calculateUtiliation_neverRevert_neverOverDP_fuzz(
        uint256 _collateralAssets,
        uint256 _debtAssets
    ) public view {
        int256 u = irm.calculateUtiliation(_collateralAssets, _debtAssets);
        assertLe(u, _DP, "neverRevert_neverOverDP <= 100%");
        assertGe(u, 0, "neverRevert_neverOverDP >= 0");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_capK_InvalidKRange -vv
    */
    function test_kink_capK_InvalidKRange() public {
        vm.expectRevert(IDynamicKinkModel.InvalidKRange.selector);
        irm.capK(0, 1, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_capK_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_kink_capK_fuzz(int256 _k, int96 _kmin, int96 _kmax) public view {
        vm.assume(_kmin <= _kmax);

        int96 cappedK = irm.capK(_k, _kmin, _kmax);

        assertGe(cappedK, _kmin, "cappedK >= kmin");
        assertLe(cappedK, _kmax, "cappedK <= kmax");
    }
}
