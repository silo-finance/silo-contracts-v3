// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ISiloConfig} from "./ISiloConfig.sol";
import {ISilo} from "./ISilo.sol";

interface IShareToken is IERC20Metadata {
    struct HookSetup {
        /// @param this is the same as in siloConfig
        address hookReceiver;
        /// @param hooks bitmap
        uint24 hooksBefore;
        /// @param hooks bitmap
        uint24 hooksAfter;
        /// @param tokenType must be one of this hooks values: COLLATERAL_TOKEN, PROTECTED_TOKEN, DEBT_TOKEN
        uint24 tokenType;
    }

    struct ShareTokenStorage {
        /// @notice Silo address for which tokens was deployed
        ISilo silo;

        /// @dev cached silo config address
        ISiloConfig siloConfig;

        /// @notice Copy of hooks setup from SiloConfig for optimisation purposes
        HookSetup hookSetup;

        bool transferWithChecks;
    }

    /// @notice Emitted every time receiver is notified about token transfer
    /// @param notificationReceiver receiver address
    /// @param success false if TX reverted on `notificationReceiver` side, otherwise true
    event NotificationSent(address indexed notificationReceiver, bool success);

    error OnlySilo();
    error OnlySiloConfig();
    error OwnerIsZero();
    error RecipientIsZero();
    error AmountExceedsAllowance();
    error RecipientNotSolventAfterTransfer();
    error SenderNotSolventAfterTransfer();
    error ZeroTransfer();

    /// @notice method for SiloConfig to synchronize hooks
    /// @param _hooksBefore hooks bitmap to trigger hooks BEFORE action
    /// @param _hooksAfter hooks bitmap to trigger hooks AFTER action
    function synchronizeHooks(uint24 _hooksBefore, uint24 _hooksAfter) external;

    /// @notice Mint method for Silo to create debt
    /// @param _owner wallet for which to mint token
    /// @param _spender wallet that asks for mint
    /// @param _amount amount of token to be minted
    function mint(address _owner, address _spender, uint256 _amount) external;

    /// @notice Burn method for Silo to close debt
    /// @param _owner wallet for which to burn token
    /// @param _spender wallet that asks for burn
    /// @param _amount amount of token to be burned
    function burn(address _owner, address _spender, uint256 _amount) external;

    /// @notice TransferFrom method for liquidation
    /// @param _from wallet from which we transferring tokens
    /// @param _to wallet that will get tokens
    /// @param _amount amount of token to transfer
    function forwardTransferFromNoChecks(address _from, address _to, uint256 _amount) external;

    /// @dev Returns the amount of tokens owned by `account`.
    /// @param _account address for which to return data
    /// @return balance of the _account
    /// @return totalSupply total supply of the token
    function balanceOfAndTotalSupply(address _account) external view returns (uint256 balance, uint256 totalSupply);

    /// @notice Returns silo address for which token was deployed
    /// @return silo address
    function silo() external view returns (ISilo silo);

    function siloConfig() external view returns (ISiloConfig silo);

    /// @notice Returns hook setup
    function hookSetup() external view returns (HookSetup memory);

    /// @notice Returns hook receiver address
    function hookReceiver() external view returns (address);

    /// @dev offset value uses by vaults to calculate the conversion rate between assets and shares
    /// it determines how many shares are minted for 1 asset eg. with offset 3, 1 asset = 1000 shares
    /// notice, that 1:1000 ratio can change for collateral shares when shares value changes eg due to interest accrual.
    /// see openzeppelin contract: contracts/token/ERC20/extensions/ERC4626.sol for more details about offset
    /// @notice this method is available since Silo Core v4.0.0
    function decimalsOffset() external view returns (uint256);
}
