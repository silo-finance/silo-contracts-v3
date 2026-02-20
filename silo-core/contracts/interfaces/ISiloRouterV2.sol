// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ISiloRouterV2 {
    /// @param _data The data to be executed.
    function multicall(bytes[] calldata _data) external payable returns (bytes[] memory results);

    /// @notice Pause the router
    /// @dev Pausing the router will prevent any actions from being executed
    function pause() external;

    /// @notice Unpause the router
    function unpause() external;
}
