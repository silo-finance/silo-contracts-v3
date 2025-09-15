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
        if (_doesIrmChanged()) {
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
        if (_doesIrmChanged()) {
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

    function assert_rcur_slope_below_ucrit() public view {
        _rule_rcur_slope_below_ucrit(_stateAfterAccrueInterest, _stateAfter);
    }

    function echidna_rcur_slope_below_ucrit() public view returns (bool) {
        assert_rcur_slope_below_ucrit();
        return true;
    }

    /// @dev Verifies slope behavior when both states are below ucrit
    /// Test: When utilization is below ucrit, slope is k
    function _rule_rcur_slope_below_ucrit(State memory _before, State memory _after) internal view {
        // Only test when both states are below ucrit
        if (int256(_before.u) >= _before.config.ucrit || int256(_after.u) >= _after.config.ucrit) {
            return; // Not applicable
        }

        // Skip if utilization didn't change
        if (_after.u == _before.u) {
            return;
        }

        // Test behavior in different regions below ucrit
        if (_before.u == 0 && _after.u != 0) {
            if (_stateAfter.rcur >= _stateBefore.rcur) return;
            else {
                console2.log("[slope_below_ucrit] first action failed");
                assert(false);
            }
        }

        // Case 1: Both states below ulow - rate should be constant at rmin
        if (_before.u < _before.config.ulow && _after.u < _after.config.ulow) {
            // Rate should stay constant at rmin regardless of utilization changes
            if(_before.rcur == _after.rcur) return;
            else {
                console2.log("[slope_below_ucrit] Case 1: Both states below ulow - rate should be constant at rmin");
                console2.log("[slope_below_ucrit] Rate should stay constant at rmin regardless of utilization");
                console2.log("[slope_below_ucrit]", _before.rcur, _after.rcur);
                assert(false);
            }
        }

        // Case 2: Both states between ulow and ucrit
        if (_before.u >= _before.config.ulow && _after.u >= _after.config.ulow) {
            int256 deltaU = _after.u - _before.u;

            // Rate should change with slope k (no alpha factor)
            if (deltaU > 0) {
                assert(_after.rcur >= _before.rcur); // Rate increases
                return;
            } else if (deltaU < 0) {
                assert(_after.rcur <= _before.rcur); // Rate decreases
                return;
            }
        }
    }

    function assert_rcur_slope_above_ucrit() public view {
        _rule_rcur_slope_above_ucrit(_stateAfterAccrueInterest, _stateAfter);
    }

    function echidna_rcur_slope_above_ucrit() public view returns (bool) {
        assert_rcur_slope_above_ucrit();
        return true;
    }

    /// @dev Verifies slope behavior when both states are above ucrit
    /// Test: When utilization is above ucrit, effective slope is k(1 + α)
    function _rule_rcur_slope_above_ucrit(State memory _before, State memory _after) internal view {
        // Only test when both states are above ucrit
        if (int256(_before.u) <= _before.config.ucrit || int256(_after.u) <= _after.config.ucrit) {
            return; // Not applicable
        }

        // Skip if utilization didn't change
        if (_after.u == _before.u) {
            return;
        }

        // When above ucrit with alpha > 0, the rate change should reflect the steeper slope
        if (_after.config.alpha != 0) {
            int256 deltaU = _stateAfter.u - _stateBefore.u;

            // The rate should change according to the effective slope k(1 + alpha)
            // This is a simplified check - exact calculation would need to account for
            // k changes and annualization factors
            if (deltaU > 0) {
                // Utilization increased, rate must increase
                assert(_after.rcur >= _before.rcur);
                return;
            } else {
                // Utilization decreased, rate must decrease
                assert(_after.rcur <= _before.rcur);
                return;
            }
        }
    }

    function assert_rcur_ucrit_crossing_up() public view {
        _rule_rcur_ucrit_crossing_up(_stateAfterAccrueInterest, _stateAfter);
    }

    function echidna_rcur_ucrit_crossing_up() public view returns (bool) {
        assert_rcur_ucrit_crossing_up();
        return true;
    }

    /// @dev Verifies rate behavior when crossing ucrit upward
    /// Test: When utilization crosses above ucrit, the α factor is applied
    function _rule_rcur_ucrit_crossing_up(State memory _before, State memory _after) internal view {
        if (_doesIrmChanged()) {
            console2.log("irm config changed");
            return;
        }

        // Only test when utilization crosses ucrit upward
        bool crossedUp = _before.u < _before.config.ucrit && _after.u >= _after.config.ucrit;

        if (!crossedUp) {
            return; // Not an upward crossing
        }

        // When crossing ucrit upward, the formula adds the α component:
        // Before: r = rmin + k(u - ulow)
        // After:  r = rmin + k(u - ulow) + k*α*(u - ucrit)

        // When alpha > 0, rate must increase due to alpha component being added
        if (_after.config.alpha != 0) {
            assert(_after.rcur >= _before.rcur);
            return;
        }
    }

    function assert_rcur_ucrit_crossing_down() public view {
        _rule_rcur_ucrit_crossing_down(_stateAfterAccrueInterest, _stateAfter);
    }

    function echidna_rcur_ucrit_crossing_down() public view returns (bool) {
        assert_rcur_ucrit_crossing_down();
        return true;
    }

    /// @dev Verifies rate behavior when crossing ucrit downward
    /// Test: When utilization crosses below ucrit, the α factor is removed
    function _rule_rcur_ucrit_crossing_down(State memory _before, State memory _after) internal view {
        if (_doesIrmChanged()) {
            console2.log("irm config changed");
            return;
        }

        // Only test when utilization crosses ucrit downward
        bool crossedDown = _before.u >= _before.config.ucrit && _after.u < _after.config.ucrit;

        if (!crossedDown) {
            return; // Not a downward crossing
        }

        // When crossing ucrit downward, the α component is removed:
        // Before: r = rmin + k(u - ulow) + k*α*(u - ucrit)
        // After:  r = rmin + k(u - ulow)

        // When alpha > 0, removing the alpha component should decrease the rate
        if (_before.config.alpha != 0) {
            assert(_after.rcur <= _before.rcur);
            return;
        }

        // When alpha = 0, there's no alpha effect to remove
    }

    function _doesIrmChanged() internal view returns (bool) {
        return _stateBefore.irmConfig != _stateAfter.irmConfig;
    }
}
