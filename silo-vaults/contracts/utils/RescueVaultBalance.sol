// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IIncentivesClaimingLogic} from "../interfaces/IIncentivesClaimingLogic.sol";
import {ISiloVault} from "../interfaces/ISiloVault.sol";

/// @title Rescue Vault Balance
/// @notice This contract rescues the balance of a vault and transfers it to a receiver if market is disconnected
contract RescueVaultBalance is IIncentivesClaimingLogic {
    address public immutable RECEIVER;
    IERC4626 public immutable MARKET;

    event VaultBalanceRescued(address indexed market, uint256 amount);
    
    error InvalidReceiverAddress();
    error InvalidMarketAddress();

    constructor(address _receiver, IERC4626 _market) {
        require(_receiver != address(0), InvalidReceiverAddress());
        require(address(_market) != address(0), InvalidMarketAddress());

        RECEIVER = _receiver;
        MARKET = _market;
    }

    /// @dev it will rescue all vault balance if the market is not present in vault deposit or withdrawal queue.
    function claimRewardsAndDistribute() external {
        // this contract is executed in the vault context, so `address(this)` is the SiloVault.
        ISiloVault vault = ISiloVault(address(this));

        // if the market is still present in the deposit (supply) or withdrawal queue, the balance must not be rescued.
        if (_isMarketInQueue()) return;

        uint256 balance = MARKET.balanceOf(address(vault));
        if (balance == 0) return; 

        try MARKET.transfer({to: RECEIVER, value: balance}) returns (bool) {
            emit VaultBalanceRescued(address(MARKET), balance);
        } catch {
            // do not lock/revert tx if transfer fails for any reason
        }
    }

    /// @dev Returns true if `MARKET` is present in the vault deposit (supply) or withdrawal queue.
    function _isMarketInQueue() internal view returns (bool) {
        ISiloVault vault = ISiloVault(address(this));
        uint256 supplyQueueLength = vault.supplyQueueLength();

        for (uint256 i; i < supplyQueueLength; i++) {
            if (vault.supplyQueue(i) == MARKET) return true;
        }

        uint256 withdrawQueueLength = vault.withdrawQueueLength();

        for (uint256 i; i < withdrawQueueLength; i++) {
            if (vault.withdrawQueue(i) == MARKET) return true;
        }

        return false;
    }
}
