// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ICheck} from "silo-core/deploy/silo/verifier/checks/ICheck.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

contract CheckIncentivesOwner is ICheck {
    ISiloConfig.ConfigData internal configData;
    string internal siloName;

    address internal gaugeOwner;
    address internal gauge;
    bool internal skipped;

    constructor(ISiloConfig.ConfigData memory _configData, bool _isSiloZero) {
        configData = _configData;
        siloName = _isSiloZero ? "silo0" : "silo1";
    }

    function checkName() external view override returns (string memory name) {
        name = string.concat(siloName, " incentives owner is a DAO multisig");
    }

    function successMessage() external view override returns (string memory message) {
        if (skipped) {
            message = "incentives are not set";
        } else {
            message = "owner is a DAO multisig";
        }
    }

    function errorMessage() external view override returns (string memory message) {
        message =
            string.concat("owner of ", Strings.toHexString(gauge), " is NOT known ", Strings.toHexString(gaugeOwner));
    }

    function execute() external override returns (bool result) {
        GaugeHookReceiver hookReceiver = GaugeHookReceiver(configData.hookReceiver);

        address protectedShareTokensGauge =
            address(hookReceiver.configuredGauges(IShareToken(configData.protectedShareToken)));

        address collateralShareTokensGauge =
            address(hookReceiver.configuredGauges(IShareToken(configData.collateralShareToken)));

        address debtShareTokensGauge = address(hookReceiver.configuredGauges(IShareToken(configData.debtShareToken)));

        if (
            collateralShareTokensGauge == address(0) && protectedShareTokensGauge == address(0)
                && debtShareTokensGauge == address(0)
        ) {
            skipped = true;
            return true;
        }

        if (!_checkIncentivesOwner(collateralShareTokensGauge)) return false;
        if (!_checkIncentivesOwner(protectedShareTokensGauge)) return false;
        if (!_checkIncentivesOwner(debtShareTokensGauge)) return false;

        return true;
    }

    function _checkIncentivesOwner(address _gauge) internal returns (bool success) {
        success = _gauge == address(0) || Ownable(_gauge).owner() == AddrLib.getAddress(AddrKey.DAO);

        if (!success) {
            gauge = _gauge;
            gaugeOwner = Ownable(_gauge).owner();
        }
    }
}
