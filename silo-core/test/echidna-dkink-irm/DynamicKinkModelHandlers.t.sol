// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {KinkCommon} from "silo-core/test/foundry/interestRateModel/kink/KinkCommon.sol";
import {Setup} from "silo-core/test/echidna-dkink-irm/base/Setup.t.sol";

/// @title DynamicKinkModelHandlers
abstract contract DynamicKinkModelHandlers is Setup {
    modifier updateState() {
        console2.log("\n===== updateState on action ======\n");
        _printIrmConfig();

        _updateStateBeforeAction();
        // it's acrue interest the action that update the state
        _siloMock.acrueInterest();
        _updateStateAfterAccrueInterest();

        // after acrue interest, we executing any action but rcomp data is already updated
        _;
        _updateStateAfterAction();
    }

    /// @notice Updates the setup of the IRM
    function updateConfig(
        int256 _ulow,
        int256 _u1,
        int256 _u2,
        int256 _ucrit,
        int256 _rmin,
        int96 _kmin,
        int96 _kmax,
        int256 _alpha,
        int256 _cminus,
        int256 _cplus,
        int256 _c1,
        // int256 _c2, // stack too deep
        int256 _dmax
    ) public {    
        console2.log("updateconfig()");

        IDynamicKinkModel.Config memory config = IDynamicKinkModel.Config({
            ulow: _ulow,
            u1: _u1,
            u2: _u2,
            ucrit: _ucrit,
            rmin: _rmin,
            kmin: _kmin,
            kmax: _kmax,
            alpha: _alpha,
            cminus: _cminus,
            cplus: _cplus,
            c1: _c1,
            c2: _u2 % _cplus, // this weird randomization is workaround for stack too deep
            dmax: _dmax
        });

        _makeConfigValid(config);

        _printConfig(config);

        DynamicKinkModel(address(_irm)).updateConfig(config);

        _stateAfter.irmConfig = address(IDynamicKinkModel(address(_irm)).irmConfig());

        _printState(_stateAfter);
    }

    function acrueInterest() public updateState {
        // already accrue in updateState
    }

    function deposit(uint128 _collateralAssets) public updateState {
        _siloMock.deposit(_collateralAssets);
    }

    function withdraw(uint128 _collateralAssets) public updateState {
        _siloMock.withdraw(_collateralAssets);
    }

    function borrow(uint128 _debtAssets) public updateState {
        _siloMock.borrow(_debtAssets);
    }

    function repay(uint128 _debtAssets) public updateState {
        _siloMock.repay(_debtAssets);
    }
}
