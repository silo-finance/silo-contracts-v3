// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {DynamicKinkModelFactory} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";
import {KinkCommon} from "silo-core/test/foundry/interestRateModel/kink/KinkCommon.sol";
import {SiloMock} from "silo-core/test/echidna-dkink-irm/mocks/SiloMock.sol";
import {KinkMock} from "silo-core/test/echidna-dkink-irm/mocks/KinkMock.sol";

/// @notice Storage contract for DynamicKinkModel test contracts
/// @dev Stores all state variables and constants used across test contracts
abstract contract Storage is KinkCommon {
    struct State {
        address irmConfig;
        IDynamicKinkModel.Config config;
        IDynamicKinkModel.ModelState modelState;
        int256 u;
        uint256 collateralAssets;
        uint256 debtAssets;
        uint256 interestRateTimestamp;
        uint256 rcur;
        uint256 rcomp;
        string name;
    }

    DynamicKinkModelFactory internal _factory;
    KinkMock internal _irm;
    SiloMock internal _siloMock;

    State internal _stateBefore;
    State internal _stateAfterAccrueInterest;
    State internal _stateAfter;

    bool internal _setupConfigWithNonZeroValues;

    constructor() {
        _stateBefore.name = "stateBefore";
        _stateAfterAccrueInterest.name = "stateAfterAccrueInterest";
        _stateAfter.name = "stateAfter";
    }

    function _UNIVERSAL_LIMIT() internal view returns (int256) {
        return IDynamicKinkModel(address(_irm)).UNIVERSAL_LIMIT();
    }

    function _RCUR_CAP() internal view returns (int256) {
        return IDynamicKinkModel(address(_irm)).RCUR_CAP();
    }

    function _ONE_YEAR() internal view returns (int256) {
        return IDynamicKinkModel(address(_irm)).ONE_YEAR();
    }

    function _RCOMP_CAP_PER_SECOND() internal view returns (int256) {
        return IDynamicKinkModel(address(_irm)).RCOMP_CAP_PER_SECOND();
    }

    function _X_MAX() internal view returns (int256) {
        return IDynamicKinkModel(address(_irm)).X_MAX();
    }
}
