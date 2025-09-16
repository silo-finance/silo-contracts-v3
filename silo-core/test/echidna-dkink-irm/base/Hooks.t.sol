// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {Storage} from "silo-core/test/echidna-dkink-irm/base/Storage.t.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/// @title BaseHooks
/// @notice Hook management for pre/post action checks
/// @dev Allows for modular testing with before/after hooks
abstract contract Hooks is Storage {
    /// @dev Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev Update state before silo state is updated
    function _updateStateBeforeAction() internal {
        _stateBefore = _stateAfter;

        _printState(_stateBefore);
    }

    function _updateStateAfterAccrueInterest() internal {
        _saveCurrentState(_stateAfterAccrueInterest);
    }

    function _updateStateAfterAction() internal {
        _saveCurrentState(_stateAfter);
    }

    function _saveCurrentState(State storage _state) internal {
        _updateSiloState(_state);

        _state.rcur = _irm.getCurrentInterestRate(address(_siloMock), block.timestamp);

        _state.rcomp = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp);

        _updateCommonState(_state);

        _printState(_state);
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

    function _printState(State memory _state) internal pure {
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
        (IDynamicKinkModel.ModelState memory modelState, IDynamicKinkModel.Config memory config) =
            IDynamicKinkModel(address(_irm)).getModelStateAndConfig();

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

    /*
    {
      "id": 0,
      "input": {
        "lastTransactionTime": 337812,
        "currentTime": 337812,
        "lastSlope": 29,
        "lastUtilization": 345371008406398333,
        "totalBorrowAmount": 130216351404093119,
        "totalDeposits": 377033243192397427
      },
      "constants": {
        "ulow": 0,
        "u1": 0,
        "u2": 1000000000000000000,
        "ucrit": 1000000000000000000,
        "rmin": 0,
        "kmin": 29,
        "kmax": 5214973493986630,
        "alpha": 0,
        "cminus": 1000000000000000000000000000,
        "cplus": 1000000000000000000000000000,
        "c1": 0,
        "c2": 1000000000000000000000000000,
        "dmax": 1000000000000000000000000000
      },
      "expected": {
        "currentAnnualInterest": 315356811
      }
    },
    */
    function printJsonTestCase() public view {
        console2.log("Json Test Case:");
        console2.log("{");
        console2.log("  \"id\": 0,");
        console2.log("  \"input\": {");
        console2.log("    \"lastTransactionTime\": ", _stateBefore.interestRateTimestamp, ",");
        console2.log("    \"currentTime\": ", block.timestamp, ",");
        console2.log("    \"lastSlope\": ", vm.toString(_stateBefore.modelState.k), ",");
        console2.log("    \"lastUtilization\": ", vm.toString(_stateBefore.u), ",");
        console2.log("    \"totalBorrowAmount\": ", _stateBefore.debtAssets, ",");
        console2.log("    \"totalDeposits\": ", _stateBefore.collateralAssets);
        console2.log("  },");
        console2.log("  \"constants\": {");
        console2.log("    \"ulow\": ", vm.toString(_stateBefore.config.ulow), ",");
        console2.log("    \"u1\": ", vm.toString(_stateBefore.config.u1), ",");
        console2.log("    \"u2\": ", vm.toString(_stateBefore.config.u2), ",");
        console2.log("    \"ucrit\": ", vm.toString(_stateBefore.config.ucrit), ",");
        console2.log("    \"rmin\": ", vm.toString(_stateBefore.config.rmin), ",");
        console2.log("    \"kmin\": ", vm.toString(_stateBefore.config.kmin), ",");
        console2.log("    \"kmax\": ", vm.toString(_stateBefore.config.kmax), ",");
        console2.log("    \"alpha\": ", vm.toString(_stateBefore.config.alpha), ",");
        console2.log("    \"cminus\": ", vm.toString(_stateBefore.config.cminus), ",");
        console2.log("    \"cplus\": ", vm.toString(_stateBefore.config.cplus), ",");
        console2.log("    \"c1\": ", vm.toString(_stateBefore.config.c1), ",");
        console2.log("    \"c2\": ", vm.toString(_stateBefore.config.c2), ",");
        console2.log("    \"dmax\": ", _stateBefore.config.dmax);
        console2.log("  },");
        console2.log("  \"expected\": {");
        console2.log("    \"currentAnnualInterest\": ", _stateAfter.rcur);
        console2.log("  }");
        console2.log("}");
    }
}
