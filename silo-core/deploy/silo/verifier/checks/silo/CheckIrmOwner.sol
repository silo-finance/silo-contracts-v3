// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ICheck} from "silo-core/deploy/silo/verifier/checks/ICheck.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";

contract CheckIrmOwner is ICheck {
    ISiloConfig.ConfigData internal configData;
    string internal siloName;
    address internal realOwner;
    bool isOwnableIrm;

    constructor(ISiloConfig.ConfigData memory _configData, bool _isSiloZero) {
        configData = _configData;
        siloName = _isSiloZero ? "silo0" : "silo1";
    }

    function checkName() external view override returns (string memory name) {
        name = string.concat(siloName, " IRM owner should be a DAO_ORACLE");
    }

    function successMessage() external view override returns (string memory message) {
        if (!isOwnableIrm) message = "IRM is NOT ownable, N/A";
        else message = string.concat("owner is a DAO_ORACLE ", Strings.toHexString(realOwner));
    }

    function errorMessage() external view override returns (string memory message) {
        message = string.concat("owner is NOT a DAO_ORACLE ", Strings.toHexString(realOwner));
    }

    function execute() external override returns (bool result) {
        Ownable irm = Ownable(configData.interestRateModel);

        try irm.owner() returns (address owner) {
            isOwnableIrm = true;
            realOwner = owner;
            // check zero in case of DAO key is not set for a new chain.
            result = owner != address(0) && owner == AddrLib.getAddress(AddrKey.DAO_ORACLE);
        } catch {
            result = true;
            isOwnableIrm = false;
        }
    }
}
