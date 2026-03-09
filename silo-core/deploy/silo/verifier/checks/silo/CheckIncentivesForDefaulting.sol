// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ICheck} from "silo-core/deploy/silo/verifier/checks/ICheck.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Utils} from "silo-core/deploy/silo/verifier/Utils.sol";


contract CheckIncentivesForDefaulting is ICheck {
    ISiloConfig.ConfigData internal configData;
    string internal siloName;

    bool internal skipped;

    constructor(ISiloConfig.ConfigData memory _configData, bool _isSiloZero) {
        configData = _configData;
        siloName = _isSiloZero ? "silo0" : "silo1";
    }

    function checkName() external view override returns (string memory name) {
        name = string.concat(siloName, " incentives for defaulting");
    }

    function successMessage() external view override returns (string memory message) {
        if (skipped) {
            message = "not needed";
        } else {
            message = "are set";
        }
    }

    function errorMessage() external pure override returns (string memory message) {
        message = " NOT set";
    }

    function execute() external override returns (bool result) {
        GaugeHookReceiver hookReceiver = GaugeHookReceiver(configData.hookReceiver);

        bool isDefaulting = Utils.isDefaultingHook(configData.hookReceiver);
        
        if (!isDefaulting) {
            skipped = true;
            return true;
        }

        bool isThisDebtSilo = configData.lt == 0;

        if (!isThisDebtSilo) {
            skipped = true;
            return true;
        }

        address collateralShareTokensGauge =
            address(hookReceiver.configuredGauges(IShareToken(configData.collateralShareToken)));

        return collateralShareTokensGauge != address(0);
    }
}
