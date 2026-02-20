// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

/// @notice Manageable oracle that allows updating the oracle address with time lock and two-owner approval
interface IManageableOracle {
    event OracleProposed(ISiloOracle indexed pendingOracle, uint256 availableAt);
    event OracleUpdated(ISiloOracle indexed oracle);
    event OracleProposalCanceled();
    event TimelockProposed(uint32 pendingTimelock, uint256 availableAt);
    event TimelockUpdated(uint32 timelock);
    event TimelockProposalCanceled();
    event OwnershipTransferProposed(address indexed newOwner, uint256 availableAt);
    event OwnershipRenounceProposed(uint256 availableAt);
    event OwnershipTransferCanceled();
    event OwnershipRenounceCanceled();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NoChange();
    error QuoteTokenMustBeTheSame();
    error BaseTokenMustBeTheSame();
    error PendingUpdate();
    error PendingOracleUpdate();
    error PendingTimelockUpdate();
    error NoPendingUpdate();
    error NoPendingUpdateToCancel();
    error TimelockNotExpired();
    error InvalidTimelock();
    error ZeroOracle();
    error ZeroOwner();
    error ZeroBaseToken();
    error InvalidOwnershipChangeType();
    error UseRenounceOwnership();
    error OracleQuoteFailed();
    error BaseTokenDecimalsMustBeGreaterThanZero();
    error OnlyOwner();

    /// @notice Initialize the ManageableOracle
    /// @param _oracle Initial oracle address
    /// @param _owner Address that will own the contract
    /// @param _timelock Initial time lock duration
    function initialize(ISiloOracle _oracle, address _owner, uint32 _timelock) external;

    /// @notice Propose a new oracle address (can only be called by owner)
    /// @param _oracle The new oracle address to propose
    function proposeOracle(ISiloOracle _oracle) external;

    /// @notice Propose a new time lock duration (can only be called by owner)
    /// @param _timelock The new time lock duration in seconds
    function proposeTimelock(uint32 _timelock) external;

    /// @notice Accept and execute the pending oracle update (can only be called by owner after time lock expires)
    function acceptOracle() external;

    /// @notice Accept and execute the pending timelock update (can only be called by owner after time lock expires)
    function acceptTimelock() external;

    /// @notice Cancel the pending oracle update (can only be called by owner)
    function cancelOracle() external;

    /// @notice Cancel the pending timelock update (can only be called by owner)
    function cancelTimelock() external;

    /// @notice Propose a new ownership transfer (can only be called by owner)
    /// @param newOwner The new owner address to propose
    function proposeTransferOwnership(address newOwner) external;

    /// @notice Propose ownership renounce (can only be called by owner)
    function proposeRenounceOwnership() external;

    /// @notice Cancel the pending ownership transfer (can only be called by owner)
    function cancelTransferOwnership() external;

    /// @notice Cancel the pending ownership renounce (can only be called by owner)
    function cancelRenounceOwnership() external;

    /// @notice The new owner accepts the ownership transfer
    /// @dev Can only be called by the pending owner after timelock expires
    function acceptOwnership() external;

    /// @notice Leaves the contract without owner
    /// @dev Can only be called by the current owner after timelock expires
    ///      NOTE: Renouncing ownership will leave the contract without an owner,
    ///      thereby disabling any functionality that is only available to the owner.
    function acceptRenounceOwnership() external;

    /// @notice Verify that the oracle is valid and can provide quotes for the base token
    /// @param _oracle Oracle address to verify
    /// @dev This function checks that:
    ///      - Oracle address is not zero
    ///      - Oracle quote token matches the stored quote token
    ///      - Oracle can provide a valid quote for the base token
    function oracleVerification(ISiloOracle _oracle) external view;

    /// @notice Get the current owner of the contract
    /// @return The address of the current owner
    function owner() external view returns (address);

    /// @notice Get the current oracle used by the manageable oracle
    /// @return The oracle used by the manageable oracle
    function oracle() external view returns (ISiloOracle);

    /// @notice Get the pending oracle address (if any)
    /// @return value The pending oracle address
    /// @return validAt The timestamp at which the pending oracle becomes valid
    function pendingOracle() external view returns (address value, uint64 validAt);

    /// @notice Get the current time lock duration
    /// @return The time lock duration in seconds
    function timelock() external view returns (uint32);

    /// @notice Get the pending time lock duration (if any)
    /// @return value The pending timelock value
    /// @return validAt The timestamp at which the pending timelock becomes valid
    function pendingTimelock() external view returns (uint192 value, uint64 validAt);

    /// @notice Get the pending ownership change (if any)
    /// @return value The pending owner address
    /// @return validAt The timestamp at which the pending ownership change becomes valid
    /// @dev If address is zero, it means pending renounce, otherwise pending transfer
    function pendingOwnership() external view returns (address value, uint64 validAt);

    /// @notice Get the base token address
    /// @return The base token address
    function baseToken() external view returns (address);

    /// @notice Get the base token decimals
    /// @return The base token decimals
    function baseTokenDecimals() external view returns (uint256);
}
