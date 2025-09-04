// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Hooks} from "silo-core/test/echidna-dkink-irm/base/Hooks.t.sol";
import {DynamicKinkModelFactory} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {SiloMock} from "silo-core/test/echidna-dkink-irm/mocks/SiloMock.sol";

import {KinkMock} from "silo-core/test/echidna-dkink-irm/mocks/KinkMock.sol";

/// @title Setup
/// @notice Deployment and initialization logic for DynamicKinkModel testing
/// @dev Handles contract deployment and initial configuration
abstract contract Setup is Hooks {
    /// @notice Deploy factory and IRM with given configuration
    function _deployDynamicKinkModel() internal virtual {
        if (address(_irm) != address(0)) {
            return;
        }

        // Deploy factory if not already deployed
        if (address(_factory) == address(0)) {
            _factory = new DynamicKinkModelFactory(new KinkMock());
        }

        // We start from the empty state
        IDynamicKinkModel.Config memory config;

        IInterestRateModel deployed = _factory.create({
            _config: config,
            _initialOwner: address(this),
            _silo: address(_siloMock),
            _externalSalt: bytes32(0)
        });

        _irm = KinkMock(address(deployed));
    }

    /// @notice Deploy Silo mock
    function _deploySiloMock() internal virtual {
        if (address(_siloMock) != address(0)) return;

        _siloMock = new SiloMock();
    }
}
