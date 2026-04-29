// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISiloConfig} from "./ISiloConfig.sol";

interface IHookReceiver {
    struct HookConfig {
        uint24 hooksBefore;
        uint24 hooksAfter;
    }

    event HookConfigured(address silo, uint24 hooksBefore, uint24 hooksAfter);

    /// @dev Revert if provided silo configuration during initialization is empty
    error EmptySiloConfig();
    /// @dev Revert if the hook receiver is already configured/initialized
    error AlreadyConfigured();
    /// @dev Revert if the caller is not a silo
    error OnlySilo();
    /// @dev Revert if the caller is not a silo or a share token
    error OnlySiloOrShareToken();

    /// @notice Initialize a hook receiver
    /// @param _siloConfig Silo configuration with all the details about the silo
    /// @param _data Data to initialize the hook receiver (if needed)
    function initialize(ISiloConfig _siloConfig, bytes calldata _data) external;

    /// @notice state of Silo before action, can be also without interest, if you need them, call silo.accrueInterest()
    function beforeAction(address _silo, uint256 _action, bytes calldata _input) external;

    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput) external;

    /// @notice return hooksBefore and hooksAfter configuration
    function hookReceiverConfig(address _silo) external view returns (uint24 hooksBefore, uint24 hooksAfter);
}
