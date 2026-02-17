// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ISiloIncentivesControllerFactory {
    event SiloIncentivesControllerCreated(address indexed controller);

    /// @notice Creates a new SiloIncentivesControllerCompatible instance.
    /// @param _owner The address of the owner of the SiloIncentivesControllerCompatible.
    /// @param _notifier The address of the notifier of the SiloIncentivesControllerCompatible.
    /// @param _shareToken The address of the share token of the SiloIncentivesControllerCompatible.
    /// @param _externalSalt The external salt to use for the creation of the incentives controller instance.
    /// @return The address of the newly created SiloIncentivesControllerCompatible.
    function create(
        address _owner,
        address _notifier,
        address _shareToken,
        bytes32 _externalSalt
    ) external returns (address);

    /// @notice Checks if a given address is a SiloIncentivesControllerCompatible.
    /// @param _controller The address to check.
    /// @return True if the address is a SiloIncentivesControllerCompatible, false otherwise.
    function isSiloIncentivesController(address _controller) external view returns (bool);
}
