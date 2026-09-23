// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {Invariants} from "silo-core/test/echidna-dkink-irm/invariants/Invariants.t.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/// @title DynamicKinkModelTester
/// @notice Main tester contract for Echidna testing of DynamicKinkModel
/// @dev Entry point that integrates all components
contract DynamicKinkModelTester is Invariants {
    constructor() payable {
        _deploySiloMock();
        _deployDynamicKinkModel();

        _siloMock.setIRM(IInterestRateModel(address(_irm)));
    }
}
