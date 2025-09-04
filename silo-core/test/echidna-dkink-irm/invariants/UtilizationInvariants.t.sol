// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {DynamicKinkModelHandlers} from "silo-core/test/echidna-dkink-irm/DynamicKinkModelHandlers.t.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/// @title UtilizationInvariants
/// @notice Implements specific invariants for the DynamicKinkModel Interest Rate Model
abstract contract UtilizationInvariants is DynamicKinkModelHandlers {
    /// @dev Utilization thresholds are properly ordered Invariant: 0 ≤ ulow ≤ u1 ≤ u2 ≤ ucrit ≤ 100%
    function assert_utilization_parameters_ordering() public view {
        (, IDynamicKinkModel.Config memory config) = _irm.getModelStateAndConfig();

        assert(0 <= config.ulow
            && config.ulow <= config.u1
            && config.u1 <= config.u2
            && config.u2 <= config.ucrit
            && config.ucrit <= int256(_DP));
    }

    function echidna_utilization_parameters_ordering() public view returns (bool) {
        assert_utilization_parameters_ordering();

        return true;
    }
}
