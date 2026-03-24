// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Immediate Distribution interface for old method with uin104 amount
interface IImmediateDistributionUint104 {
    /// @notice Immediately distributes rewards to the incentives program
    /// @param _tokenToDistribute The token to distribute
    /// @param _amount The amount of rewards to distribute
    function immediateDistribution(address _tokenToDistribute, uint104 _amount) external;
}
