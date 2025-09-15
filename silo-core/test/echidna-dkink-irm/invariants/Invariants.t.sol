// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RcurInvariants} from "silo-core/test/echidna-dkink-irm/invariants/RcurInvariants.t.sol";
import {RcompInvariants} from "silo-core/test/echidna-dkink-irm/invariants/RcompInvariants.t.sol";
import {UtilizationInvariants} from "silo-core/test/echidna-dkink-irm/invariants/UtilizationInvariants.t.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/// @title Invariants
/// @notice Main invariant wrapper contract that combines all components
/// @dev This is the entry point for Echidna testing
contract Invariants is RcurInvariants, RcompInvariants, UtilizationInvariants {
    /// @notice All coefficients are non-negative
    /// @dev Invariants:
    /// c1, c2, c+, c− ≥ 0
    /// dmax ≥ c2
    /// 0 ≤ kmin ≤ kmax
    function assets_coefficient_non_negative() public view {
        IDynamicKinkModel.Config memory config = _irm.irmConfig().getConfig();

        assert(config.c1 >= 0 
            && config.c2 >= 0 
            && config.cplus >= 0 
            && config.cminus >= 0 
            && config.dmax >= config.c2 && config.kmin >= 0 && config.kmin <= config.kmax);
    }

    function echidna_coefficient_non_negative() public view returns (bool) {
        assets_coefficient_non_negative();

        return true;
    }

    function assert_silo_never_changes() public view {
        if (address(_irm.irmConfig()) == address(0)) return;

        (, address silo) = _irm.modelState();

        assert(silo == address(_siloMock));
    }

    /// @notice Silo never changes
    /// @dev Invariants:
    /// If silo changes, it is only from address(0) to an address but not the other way around.
    function echidna_silo_never_changes() public view returns (bool) {
        assert_silo_never_changes();

        return true;
    }
}
