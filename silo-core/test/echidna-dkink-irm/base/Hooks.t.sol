// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {Storage} from "silo-core/test/echidna-dkink-irm/base/Storage.t.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/// @title BaseHooks
/// @notice Hook management for pre/post action checks
/// @dev Allows for modular testing with before/after hooks
abstract contract Hooks is Storage {
    /// @dev Update state before silo state is updated
    function _updateStateBeforeAction() internal {
        _updateCommonState(_stateBefore);

        _stateBefore.rcur = _stateAfter.rcur;
        _stateBefore.rcomp = _stateAfter.rcomp;
        _updateSiloState(_stateBefore);

        _printState(_stateBefore);
    }

    function _updateStateAfterAction() internal {
        _updateSiloState(_stateAfter);

        _stateAfter.rcur = _irm.getCurrentInterestRate(address(_siloMock), block.timestamp);

        _stateAfter.rcomp = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp);

        _updateCommonState(_stateAfter);

        _printState(_stateAfter);
    }

    /// @dev Update state after silo state is updated
    function _updateCommonState(State storage _state) internal {
        if (address(_irm) == address(0)) {
            console2.log("IRM not initialized, no state update");
            return;
        }

        (_state.modelState, _state.config) = IDynamicKinkModel(address(_irm)).getModelStateAndConfig();

        _state.u = _calculateUtiliation();
        _state.irmConfig = address(IDynamicKinkModel(address(_irm)).irmConfig());
    }

    /// @dev Update state before silo state is updated
    function _updateSiloState(State storage _state) internal {
        ISilo.UtilizationData memory utilizationData = _siloMock.utilizationData();

        _state.collateralAssets = utilizationData.collateralAssets;
        _state.debtAssets = utilizationData.debtAssets;
        _state.interestRateTimestamp = utilizationData.interestRateTimestamp;
    }

    /// @dev Calculates utilization for internal testing
    function _calculateUtiliation() internal view returns (int256) {
        ISilo.UtilizationData memory utilizationData = _siloMock.utilizationData();
        return _irm.calculateUtiliation(utilizationData.collateralAssets, utilizationData.debtAssets);
    }

    function _printState(State memory _state) internal view {
        console2.log("State: %s", _state.name);
        console2.log("  collateralAssets:", _state.collateralAssets);
        console2.log("  debtAssets:", _state.debtAssets);
        console2.log("  LTV:", _state.collateralAssets == 0 ? 0 : _state.debtAssets * 1e18 / _state.collateralAssets);
        console2.log("  interestRateTimestamp:", _state.interestRateTimestamp);
        console2.log("  u:", _state.u);
        console2.log("  rcur:", _state.rcur);
        console2.log("  rcomp:", _state.rcomp);
        console2.log("  irmConfig:", _state.irmConfig);
        console2.log("------");
    }

    function _printIrmConfig() internal view {
        (
            IDynamicKinkModel.ModelState memory modelState,
            IDynamicKinkModel.Config memory config
        ) = IDynamicKinkModel(address(_irm)).getModelStateAndConfig();

        console2.log("IRM Config:");
        console2.log("  ulow:  ", config.ulow);
        console2.log("  u1:    ", config.u1);
        console2.log("  u2:    ", config.u2);
        console2.log("  ucrit: ", config.ucrit);
        console2.log("  rmin: ", config.rmin);
        console2.log("  kmin: ", config.kmin);
        console2.log("  kmax: ", config.kmax);
        console2.log("  alpha:", config.alpha);
        console2.log("  cminus: ", config.cminus);
        console2.log("  cplus:  ", config.cplus);
        console2.log("  c1:     ", config.c1);
        console2.log("  c2:     ", config.c2);
        console2.log("  dmax:", config.dmax);
        console2.log("  k:", modelState.k);
    }    
}
