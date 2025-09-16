// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {DynamicKinkModelHandlers} from "silo-core/test/echidna-dkink-irm/DynamicKinkModelHandlers.t.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/// @title RcompInvariants
/// @notice Implements specific invariants for the DynamicKinkModel Interest Rate Model
abstract contract RcompInvariants is DynamicKinkModelHandlers {
    /// @dev Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function assert_rcomp_bounds(uint24 _timeAddition) public view {
        uint256 rcomp = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp + _timeAddition);
        assert(rcomp <= _siloMock.calculateMaxRcomp(block.timestamp + _timeAddition));
    }

    function echidna_rcomp_bounds() public view returns (bool) {
        assert_rcomp_bounds(0);

        return true;
    }

    // compoundInterestRate = 0 => currentInterestRate = 0;
    function assert_rcomp_zero_then_rcur_zero() internal view {
        // _siloMock.accrueInterest(); ??
        uint256 rcomp = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp);
        uint256 rcur = _irm.getCurrentInterestRate(address(_siloMock), block.timestamp);

        if (rcomp == 0) {
            if (rcur != 0) {
                console2.log("rcomp == 0 but rcur != 0");
                assert(false);
            }
        }
    }

    function echidna_rcomp_zero_then_rcur_zero() public view returns (bool) {
        assert_rcomp_zero_then_rcur_zero();
        return true;
    }

    /*
    We make two consecutive calls of function rcomp. Both calls must be made with the same difference t1-t0.
    The first call takes any valid u_before and k_before as input. The output is rcomp_1 and k_after.
    After that, we select an arbitrary u_after and call function rcomp again. The output is rcomp_2.
    We need to check the conditions:
    1) if u_before <= u_after and k_before <= k_after, then rcomp_1 <= rcomp_2,
    2) if u_before >= u_after and k_before >= k_after, then rcomp_1 >= rcomp_2.

    To clarify, this is the scenario:
    1. Initialize silo with random state. Utilization is u_before, value of k is k_before.
    2. Warp T seconds.
    3. Query rcomp(), it returns rcomp_1.
    4. Accrue interest.
    5. Do random transactions.
    6. Check utilization and k, call it u_after and k_after.
    7. Warp the same T seconds.
    8. Query rcomp(), it returns rcomp_2.
    9. Check Alexey’s rules.
    */
    function assert_rcomp_monotonicity(uint32 _warp, uint8 _action, uint128 _assets) public {
        _siloMock.accrueInterest(); // this is our starting point for warp

        vm.warp(block.timestamp + _warp);
        (int256 kBefore, int256 uBefore) = _pullKandUtilization();
        uint256 rcomp1 = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp);

        _siloMock.accrueInterest();
        // action
        _siloMock.doRandomAction(_action, _assets);

        (int256 kAfter, int256 uAfter) = _pullKandUtilization();

        vm.warp(block.timestamp + _warp);
        uint256 rcomp2 = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp);

        if (uBefore <= uAfter && kBefore <= kAfter) {
            console2.log("uBefore <= uAfter && kBefore <= kAfter");
            assert(rcomp1 <= rcomp2);
        } else if (uBefore >= uAfter && kBefore >= kAfter) {
            console2.log("uBefore >= uAfter && kBefore >= kAfter");
            assert(rcomp1 >= rcomp2);
        }
    }

    function _pullKandUtilization() internal view returns (int256 k, int256 u) {
        (IDynamicKinkModel.ModelState memory modelState, IDynamicKinkModel.Config memory config) =
            _irm.getModelStateAndConfig();
        k = modelState.k;
        u = _calculateUtiliation();
    }
}
