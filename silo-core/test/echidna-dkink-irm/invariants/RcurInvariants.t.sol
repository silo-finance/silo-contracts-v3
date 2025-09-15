// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {DynamicKinkModelHandlers} from "silo-core/test/echidna-dkink-irm/DynamicKinkModelHandlers.t.sol";

/// @title RcurInvariants
/// @notice Implements specific invariants for the DynamicKinkModel Interest Rate Model
abstract contract RcurInvariants is DynamicKinkModelHandlers {
    function assert_rcur_bounds(uint256 _timeAddition) public view {
        uint256 rcur = _irm.getCurrentInterestRate(address(_siloMock), block.timestamp + _timeAddition);
        assert(rcur <= uint256(_RCUR_CAP()));
    }

    /// @dev Current interest rate must be within valid bounds
    function echidna_rcur_bounds() external view returns (bool) {
        assert_rcur_bounds(0);

        return true;
    }

    function assert_when_u_grow_rcur_grow_afterAction() public view {
        _when_u_grow_rcur_grow(_stateAfterAccrueInterest, _stateAfter);
    }

    /// @dev If utilization grows while remaining above u1, or jumps from below u1 to above u1, then rcur grows or stays the same.
    function _when_u_grow_rcur_grow(State memory _before, State memory _after) internal view {
        if (_before.irmConfig != _after.irmConfig) {
            console2.log("irm config changed, we can not compare");
            return;
        }

        bool uGrow = _before.u < _after.u;

        if (!uGrow) {
            console2.log("utilization did not grow");
            return;
        }
        if (_after.u < _after.config.u1) {
            console2.log("utilization is below u1, rule does not apply for this case");
            return;
        }

        console2.log("    prev state u", _before.u);
        console2.log(" current state u", _after.u);
        console2.log("    prev state rcur", _before.rcur);
        console2.log(" current state rcur", _after.rcur);

        // we accept 0 as response, because it can happen in case of overflow
        assert(_after.rcur == 0 || _before.rcur <= _after.rcur);
        // assert(false); // debug: does it run?
        // if (_before.rcur < _after.rcur) assert(false); // debug: if we have case whre it grows
    }

    function echidna_when_u_grow_rcur_grow_afterAction() public view returns (bool) {
        assert_when_u_grow_rcur_grow_afterAction();
        return true;
    }

    function assert_when_u_decrease_rcur_decrease_afterAction() public view {
        _when_u_decrease_rcur_decrease(_stateAfterAccrueInterest, _stateAfter);
    }

    function echidna_when_u_decrease_rcur_decrease_afterAction() public view returns (bool) {
        assert_when_u_decrease_rcur_decrease_afterAction();
        return true;
    }

    function _when_u_decrease_rcur_decrease(State memory _before, State memory _after) internal view {
        if (_before.irmConfig != _after.irmConfig) {
            console2.log("irm config changed");
            return;
        }

        bool uDecrease = _before.u > _after.u;

        if (!uDecrease) return;
        if (_after.u >= _after.config.u2) return;

        console2.log("    prev state u", _before.u);
        console2.log(" current state u", _after.u);
        console2.log("    prev state rcur", _before.rcur);
        console2.log(" current state rcur", _after.rcur);

        assert(_after.rcur < _before.rcur);
        // assert(false); // does it run?
        // if (_before.rcur > _after.rcur) assert(false); // debug: if we have case whre it grows   
    }

    /// @dev Interest rate increases monotonically with utilization
    /// Invariant: For any u1 < u2, calculateRate(u1, k) ≤ calculateRate(u2, k)
    /// not true, because in case of overflow, we will return 0, also on full repay we will return 0
    // function echidna_rcur_monotonicity() public view returns (bool) {
    //     if (_stateBefore.u < _stateAfter.u) {
    //         return _stateBefore.rcur <= _stateAfter.rcur;
    //     }

    //     if (_stateBefore.u > _stateAfter.u) {
    //         return _stateBefore.rcur >= _stateAfter.rcur;
    //     }

    //     return true;
    // }

    /// @dev Verifies slope behavior when both states are below ucrit
    /// Test: When utilization is below ucrit, slope is k
    // function echidna_rcur_slope_below_ucrit() public view returns (bool) {
    //     State memory stateAfter;

    //     stateAfter.u = _calculateUtiliation();
    //     (stateAfter.modelState, stateAfter.config) = _irm.getModelStateAndConfig();
    //     stateAfter.rcur = _irm.getCurrentInterestRate(address(_siloMock), block.timestamp);

    //     // Only test when both states are below ucrit
    //     if (int256(_stateBefore.u) >= _stateBefore.config.ucrit || int256(stateAfter.u) >= stateAfter.config.ucrit) {
    //         return true; // Not applicable
    //     }

    //     // Skip if utilization didn't change
    //     if (stateAfter.u == _stateBefore.u) {
    //         return true;
    //     }

    //     // Test behavior in different regions below ucrit
    //     if (_stateBefore.u == 0 && stateAfter.u != 0) {
    //         return stateAfter.rcur >= _stateBefore.rcur;
    //     }

    //     // Case 1: Both states below ulow - rate should be constant at rmin
    //     if (_stateBefore.u < _stateBefore.config.ulow && stateAfter.u < stateAfter.config.ulow) {
    //         // Rate should stay constant at rmin regardless of utilization changes
    //         return stateAfter.rcur == _stateBefore.rcur;
    //     }

    //     // Case 2: Both states between ulow and ucrit
    //     if (_stateBefore.u >= _stateBefore.config.ulow && stateAfter.u >= stateAfter.config.ulow) {
    //         int256 deltaU = stateAfter.u - _stateBefore.u;

    //         // Rate should change with slope k (no alpha factor)
    //         if (deltaU > 0) {
    //             return stateAfter.rcur >= _stateBefore.rcur; // Rate increases
    //         } else if (deltaU < 0) {
    //             return stateAfter.rcur <= _stateBefore.rcur; // Rate decreases
    //         }
    //     }

    //     return true;
    // }

    // /// @dev Verifies slope behavior when both states are above ucrit
    // /// Test: When utilization is above ucrit, effective slope is k(1 + α)
    // function echidna_rcur_slope_above_ucrit() public view returns (bool) {
    //     // Only test when both states are above ucrit
    //     if (int256(_stateBefore.u) <= _stateBefore.config.ucrit || int256(_stateAfter.u) <= _stateAfter.config.ucrit) {
    //         return true; // Not applicable
    //     }

    //     // Skip if utilization didn't change
    //     if (_stateAfter.u == _stateBefore.u) {
    //         return true;
    //     }

    //     // When above ucrit with alpha > 0, the rate change should reflect the steeper slope
    //     if (_stateAfter.config.alpha != 0) {
    //         int256 deltaU = _stateAfter.u - _stateBefore.u;

    //         // The rate should change according to the effective slope k(1 + alpha)
    //         // This is a simplified check - exact calculation would need to account for
    //         // k changes and annualization factors
    //         if (deltaU > 0) {
    //             // Utilization increased, rate must increase
    //             return _stateAfter.rcur >= _stateBefore.rcur;
    //         } else {
    //             // Utilization decreased, rate must decrease
    //             return _stateAfter.rcur <= _stateBefore.rcur;
    //         }
    //     }

    //     return true;
    // }

    // /// @dev Verifies rate behavior when crossing ucrit upward
    // /// Test: When utilization crosses above ucrit, the α factor is applied
    // function echidna_rcur_ucrit_crossing_up() public view returns (bool) {
    //     // Only test when utilization crosses ucrit upward
    //     bool crossedUp = _stateBefore.u < _stateBefore.config.ucrit &&
    //                     _stateAfter.u >= _stateAfter.config.ucrit;

    //     if (!crossedUp) {
    //         return true; // Not an upward crossing
    //     }

    //     // When crossing ucrit upward, the formula adds the α component:
    //     // Before: r = rmin + k(u - ulow)
    //     // After:  r = rmin + k(u - ulow) + k*α*(u - ucrit)

    //     // When alpha > 0, rate must increase due to alpha component being added
    //     if (_stateAfter.config.alpha != 0 && _lastCallFnSig != DynamicKinkModel.updateConfig.selector) {
    //         return _stateAfter.rcur >= _stateBefore.rcur;
    //     }

    //     return true;
    // }

    // /// @dev Verifies rate behavior when crossing ucrit downward
    // /// Test: When utilization crosses below ucrit, the α factor is removed
    // function echidna_rcur_ucrit_crossing_down() public view returns (bool) {
    //     // Only test when utilization crosses ucrit downward
    //     bool crossedDown = _stateBefore.u >= _stateBefore.config.ucrit &&
    //                       _stateAfter.u < _stateAfter.config.ucrit;

    //     if (!crossedDown) {
    //         return true; // Not a downward crossing
    //     }

    //     // When crossing ucrit downward, the α component is removed:
    //     // Before: r = rmin + k(u - ulow) + k*α*(u - ucrit)
    //     // After:  r = rmin + k(u - ulow)

    //     // When alpha > 0, removing the alpha component should decrease the rate
    //     if (_stateBefore.config.alpha != 0 && _lastCallFnSig != DynamicKinkModel.updateConfig.selector) {
    //         return _stateAfter.rcur <= _stateBefore.rcur;
    //     }

    //     // When alpha = 0, there's no alpha effect to remove
    //     return true;
    // }
}
