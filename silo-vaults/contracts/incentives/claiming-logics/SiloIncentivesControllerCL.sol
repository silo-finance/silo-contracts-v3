// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {
    ISiloIncentivesController,
    IDistributionManager
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {IIncentivesClaimingLogic} from "../../interfaces/IIncentivesClaimingLogic.sol";

/// @title Silo incentives controller claiming logic
contract SiloIncentivesControllerCL is IIncentivesClaimingLogic {
    /// @notice Distributes rewards to vault depositors
    ISiloIncentivesController public immutable VAULT_INCENTIVES_CONTROLLER;
    /// @notice Distributes rewards to silo depositors
    ISiloIncentivesController public immutable SILO_INCENTIVES_CONTROLLER;

    constructor(
        address _vaultIncentivesController,
        address _siloIncentivesController
    ) {
        require(_vaultIncentivesController != address(0), VaultIncentivesControllerZeroAddress());
        require(_siloIncentivesController != address(0), SiloIncentivesControllerZeroAddress());

        VAULT_INCENTIVES_CONTROLLER = ISiloIncentivesController(_vaultIncentivesController);
        SILO_INCENTIVES_CONTROLLER = ISiloIncentivesController(_siloIncentivesController);
    }

    function claimRewardsAndDistribute() external virtual {
        IDistributionManager.AccruedRewards[] memory accruedRewards =
            SILO_INCENTIVES_CONTROLLER.claimRewards(address(VAULT_INCENTIVES_CONTROLLER));

        for (uint256 i = 0; i < accruedRewards.length; i++) {
            if (accruedRewards[i].amount == 0) continue;

            VAULT_INCENTIVES_CONTROLLER.immediateDistribution(
                accruedRewards[i].rewardToken,
                accruedRewards[i].amount
            );
        }
    }
}
