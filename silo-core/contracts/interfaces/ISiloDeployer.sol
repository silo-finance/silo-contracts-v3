// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IDynamicKinkModel} from "./IDynamicKinkModel.sol";
import {ISiloConfig} from "./ISiloConfig.sol";

/// @notice Silo Deployer
interface ISiloDeployer {
    /// @dev Details of the oracle creation transaction
    struct OracleCreationTxData {
        address deployed; // if oracle is already deployed, this will be the address to use
        address factory; // oracle factory (chainlinkV3, uniswapV3, etc)
        bytes txInput; // fn input `abi.encodeCall(fn, params...)`
    }

    /// @dev Hook receiver to be cloned and initialized during the Silo creation
    struct ClonableHookReceiver {
        address implementation;
        bytes initializationData;
    }

    /// @dev Oracles to be create during the Silo creation.
    /// If an oracle for the provided config is already created an oracle factory will return its address.
    struct Oracles {
        OracleCreationTxData solvencyOracle0;
        OracleCreationTxData maxLtvOracle0;
        OracleCreationTxData solvencyOracle1;
        OracleCreationTxData maxLtvOracle1;
    }

    /// @dev DKinkIRM config to be created during the Silo creation.
    struct DKinkIRMConfig {
        IDynamicKinkModel.Config config;
        IDynamicKinkModel.ImmutableArgs immutableArgs;
        address initialOwner;
    }

    /// @dev Emit after the Silo creation
    event SiloCreated(ISiloConfig siloConfig);

    /// @dev Revert if an oracle factory fails to create an oracle
    error FailedToCreateAnOracle(address _factory);

    /// @dev Revert if for the deployment provided both hook receiver and hook receiver implementation
    error HookReceiverMisconfigured();

    /// @dev Revert if the hook initialization data is different from expected
    error InvalidHookInitData();

    /// @notice Deploy silo
    /// @param _oracles Oracles to be create during the silo creation
    /// @param _irmConfigData0 IRM config data for a silo `_TOKEN0`
    /// @param _irmConfigData1 IRM config data for a silo `_TOKEN1`
    /// @param _clonableHookReceiver Hook receiver implementation to clone (ignored if implementation has address(0))
    /// @param _siloInitData Silo configuration for the silo creation
    function deploy(
        Oracles calldata _oracles,
        bytes calldata _irmConfigData0,
        bytes calldata _irmConfigData1,
        ClonableHookReceiver calldata _clonableHookReceiver,
        ISiloConfig.InitData memory _siloInitData
    )
        external
        returns (ISiloConfig siloConfig);
}
