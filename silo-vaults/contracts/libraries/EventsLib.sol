// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISiloVault} from "../interfaces/ISiloVault.sol";
import {FlowCapsConfig} from "../interfaces/IPublicAllocator.sol";

/// @title EventsLib
/// @dev Forked with gratitude from Morpho Labs.
/// @author Silo Labs
/// @custom:contact security@silo.finance
/// @notice Library exposing events.
library EventsLib {
    /// @notice Emitted when a pending `newTimelock` is submitted.
    event SubmitTimelock(uint256 newTimelock);

    /// @notice Emitted when `timelock` is set to `newTimelock`.
    event SetTimelock(address indexed caller, uint256 newTimelock);

    /// @notice Emitted `fee` is set to `newFee`.
    event SetFee(address indexed caller, uint256 newFee);

    /// @notice Emitted when a new `newFeeRecipient` is set.
    event SetFeeRecipient(address indexed newFeeRecipient);

    /// @notice Emitted when a pending `newGuardian` is submitted.
    event SubmitGuardian(address indexed newGuardian);

    /// @notice Emitted when `guardian` is set to `newGuardian`.
    event SetGuardian(address indexed caller, address indexed guardian);

    /// @notice Emitted when a pending `cap` is submitted for `market`.
    event SubmitCap(address indexed caller, IERC4626 indexed market, uint256 cap);

    /// @notice Emitted when a new `cap` is set for `market`.
    event SetCap(address indexed caller, IERC4626 indexed market, uint256 cap);

    /// @notice Emitted when the market's last total assets is updated to `updatedTotalAssets`.
    event UpdateLastTotalAssets(uint256 updatedTotalAssets);

    /// @notice Emitted when the `market` is submitted for removal.
    event SubmitMarketRemoval(address indexed caller, IERC4626 indexed market);

    /// @notice Emitted when `curator` is set to `newCurator`.
    event SetCurator(address indexed newCurator);

    /// @notice Emitted when an `allocator` is set to `isAllocator`.
    event SetIsAllocator(address indexed allocator, bool isAllocator);

    /// @notice Emitted when a `pendingTimelock` is revoked.
    event RevokePendingTimelock(address indexed caller);

    /// @notice Emitted when a `pendingCap` for the `market` is revoked.
    event RevokePendingCap(address indexed caller, IERC4626 indexed market);

    /// @notice Emitted when a `pendingGuardian` is revoked.
    event RevokePendingGuardian(address indexed caller);

    /// @notice Emitted when a pending market removal is revoked.
    event RevokePendingMarketRemoval(address indexed caller, IERC4626 indexed market);

    /// @notice Emitted when the `supplyQueue` is set to `newSupplyQueue`.
    event SetSupplyQueue(address indexed caller, IERC4626[] newSupplyQueue);

    /// @notice Emitted when the `withdrawQueue` is set to `newWithdrawQueue`.
    event SetWithdrawQueue(address indexed caller, IERC4626[] newWithdrawQueue);

    /// @notice Emitted when a reallocation supplies assets to the `market`.
    /// @param market The market address.
    /// @param suppliedAssets The amount of assets supplied to the market.
    /// @param suppliedShares The amount of shares minted.
    event ReallocateSupply(
        address indexed caller, IERC4626 indexed market, uint256 suppliedAssets, uint256 suppliedShares
    );

    /// @notice Emitted when a reallocation withdraws assets from the `market`.
    /// @param market The market address.
    /// @param withdrawnAssets The amount of assets withdrawn from the market.
    /// @param withdrawnShares The amount of shares burned.
    event ReallocateWithdraw(
        address indexed caller, IERC4626 indexed market, uint256 withdrawnAssets, uint256 withdrawnShares
    );

    /// @notice Emitted when interest are accrued.
    /// @param newTotalAssets The assets of the market after accruing the interest but before the interaction.
    /// @param feeShares The shares minted to the fee recipient.
    event AccrueInterest(uint256 newTotalAssets, uint256 feeShares);

    /// @notice Emitted when a new SiloVault market is created.
    /// @param SiloVault The address of the SiloVault market.
    /// @param caller The caller of the function.
    /// @param initialOwner The initial owner of the SiloVault market.
    /// @param initialTimelock The initial timelock of the SiloVault market.
    /// @param asset The address of the underlying asset.
    /// @param name The name of the SiloVault market.
    /// @param symbol The symbol of the SiloVault market.
    event CreateSiloVault(
        address indexed SiloVault,
        address indexed caller,
        address initialOwner,
        uint256 initialTimelock,
        address indexed asset,
        string name,
        string symbol
    );

    event VaultIncentiveModule(address indexed siloVault, address indexed vaultIncentiveModule);

    event CreateIdleVault(address indexed idleVault, address indexed vault);

    /// @notice Emitted during a public reallocation for each withdrawn-from market.
    event PublicWithdrawal(
        address indexed sender, ISiloVault indexed vault, IERC4626 indexed market, uint256 withdrawnAssets
    );

    /// @notice Emitted at the end of a public reallocation.
    event PublicReallocateTo(
        address indexed sender, ISiloVault indexed vault, IERC4626 indexed supplyMarket, uint256 suppliedAssets
    );

    /// @notice Emitted when the admin is set for a vault.
    event SetAdmin(address indexed sender, ISiloVault indexed vault, address admin);

    /// @notice Emitted when the fee is set for a vault.
    event SetFee(address indexed sender, ISiloVault indexed vault, uint256 fee);

    /// @notice Emitted when the fee is transferred for a vault.
    event TransferFee(address indexed sender, ISiloVault indexed vault, uint256 amount, address indexed feeRecipient);

    /// @notice Emitted when the flow caps are set for a vault.
    event SetFlowCaps(address indexed sender, ISiloVault indexed vault, FlowCapsConfig[] config);

    event SetArbitraryLossThreshold(address indexed caller, uint256 acceptableLoss);

    /// @notice Emitted when the balance tracker is synced for a market.
    event SyncBalanceTracker(IERC4626 indexed market, uint256 oldBalance, uint256 newBalance);
}
