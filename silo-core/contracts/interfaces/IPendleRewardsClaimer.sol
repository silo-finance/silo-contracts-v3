// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

interface IPendleRewardsClaimer is IHookReceiver {
    event FailedToClaimIncentives(ISilo _silo);

    error CollateralDepositNotAllowed();
    error IncentivesControllerRequired();
    error WrongSiloConfig();
    error TransitionProtectedCollateralNotAllowed();

    /// @notice Redeem rewards from Pendle
    /// @return rewardTokens Reward tokens
    /// @return rewards Rewards for collateral token
    function redeemRewards() external returns (address[] memory rewardTokens, uint256[] memory rewards);
}
