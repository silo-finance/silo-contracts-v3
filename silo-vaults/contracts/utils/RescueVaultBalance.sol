// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IIncentivesClaimingLogic} from "../interfaces/IIncentivesClaimingLogic.sol";
import {ISiloVault} from "../interfaces/ISiloVault.sol";

/// @title Rescue Vault Balance
/// @notice This contract rescues the balance of a vault and transfers it to a receiver if market is disconnected
contract RescueVaultBalance is IIncentivesClaimingLogic {
    address public immutable RECEIVER;
    IERC4626 public immutable MARKET;

    event VaultBalanceRescued(address indexed token, uint256 amount);
    
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
        if (_isMarketInQueue(vault)) return;

        IERC20 token = IERC20(IERC4626(address(vault)).asset());

        uint256 balance = token.balanceOf(address(vault));
        if (balance == 0) return; 

        try token.transfer(RECEIVER, balance) {
            emit VaultBalanceRescued(address(token), balance);
        } catch {
            // do not lock/revert tx if transfer fails for any reason
        }
    }

    /// @dev Returns true if `MARKET` is present in the vault deposit (supply) or withdrawal queue.
    function _isMarketInQueue(ISiloVault _vault) internal view returns (bool) {
        uint256 supplyQueueLength = _vault.supplyQueueLength();

        for (uint256 i; i < supplyQueueLength; i++) {
            if (_vault.supplyQueue(i) == MARKET) return true;
        }

        uint256 withdrawQueueLength = _vault.withdrawQueueLength();

        for (uint256 i; i < withdrawQueueLength; i++) {
            if (_vault.withdrawQueue(i) == MARKET) return true;
        }

        return false;
    }
}
