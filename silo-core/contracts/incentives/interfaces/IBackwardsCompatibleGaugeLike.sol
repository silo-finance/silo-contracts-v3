// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @dev Interface for incentives controller to be backwards compatible with older versions of GaugeLike controller
interface IBackwardsCompatibleGaugeLike {
    /**
     * @dev Silo share token event handler
     * @param _sender The address of the sender
     * @param _senderBalance The balance of the sender
     * @param _recipient The address of the recipient
     * @param _recipientBalance The balance of the recipient
     * @param _totalSupply The total supply of the asset in the lending pool
     * @param _amount The amount of the transfer
     */
    function afterTokenTransfer(
        address _sender,
        uint256 _senderBalance,
        address _recipient,
        uint256 _recipientBalance,
        uint256 _totalSupply,
        uint256 _amount
    ) external;

    /// @notice Kills the gauge
    function killGauge() external;

    /// @notice Un kills the gauge
    function unkillGauge() external;

    // solhint-disable func-name-mixedcase
    function share_token() external view returns (address);

    function is_killed() external view returns (bool);
}
