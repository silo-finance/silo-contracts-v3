// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {
    ISiloIncentivesController,
    IDistributionManager
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {IIncentivesClaimingLogic} from "../../interfaces/IIncentivesClaimingLogic.sol";
import {IImmediateDistributionUint104} from "../../interfaces/IImmediateDistributionUint104.sol";

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
            uint256 amount = accruedRewards[i].amount;
            if (amount == 0) continue;

            try VAULT_INCENTIVES_CONTROLLER.immediateDistribution(
                accruedRewards[i].rewardToken, 
                amount
            ) {
                // OK
            }
            catch {
                require(amount <= type(uint104).max, AmountOverflow());

                // try to use the old method
                IImmediateDistributionUint104(address(VAULT_INCENTIVES_CONTROLLER))
                    .immediateDistribution({
                        _tokenToDistribute: accruedRewards[i].rewardToken,
                        // safe cast, because we checked that amount is not greater than type(uint104).max
                        // forge-lint: disable-next-line(unsafe-typecast)
                        _amount: uint104(amount)
                    });
            }
        }
    }
}
