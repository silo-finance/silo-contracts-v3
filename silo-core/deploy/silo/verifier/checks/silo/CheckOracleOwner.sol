// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ICheck} from "silo-core/deploy/silo/verifier/checks/ICheck.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";

contract CheckOracleOwner is ICheck {
    ISiloConfig.ConfigData internal configData;
    string internal siloName;
    address internal realOwner;
    bool skip;

    constructor(ISiloConfig.ConfigData memory _configData, bool _isSiloZero) {
        configData = _configData;
        siloName = _isSiloZero ? "silo0" : "silo1";
    }

    function checkName() external view override returns (string memory name) {
        name = string.concat(siloName, " Oracle owner should be a DAO_ORACLE");
    }

    function successMessage() external view override returns (string memory message) {
        if (skip) message = "N/A";
        else message = "owner is a DAO_ORACLE";
    }

    function errorMessage() external view override returns (string memory message) {
        message = string.concat("owner is NOT a DAO_ORACLE ", Strings.toHexString(realOwner));
    }

    function execute() external override returns (bool result) {
        Ownable oracle = Ownable(configData.solvencyOracle);
        if (address(oracle) == address(0)) {
            skip = true;
            return true;
        }

        try oracle.owner() returns (address owner) {
            realOwner = owner;
            // check zero in case of DAO key is not set for a new chain.
            result = owner != address(0) && owner == AddrLib.getAddress(AddrKey.DAO_ORACLE);
        } catch {
            result = true;
            skip = true;
        }
    }
}
