// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Incentives Claiming Logic interface
interface IIncentivesClaimingLogic {
    error VaultIncentivesControllerZeroAddress();
    error SiloIncentivesControllerZeroAddress();
    error AmountOverflow();

    /// @notice Claim and distribute rewards to the vault.
    /// @dev Can claim rewards from multiple sources and distribute them to the vault users.
    function claimRewardsAndDistribute() external;
}
