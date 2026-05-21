// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

/// @title Rescue Module for Leverage Operations
/// @notice This contract collects and distributes revenue from leveraged operations.
contract RescueTokens {
    using SafeERC20 for IERC20;

    address public immutable TOKEN_RECEIVER;

    /// @notice Emitted when tokens are rescued
    /// @param token Address of the token
    /// @param amount Amount rescued
    event TokensRescued(address indexed token, uint256 amount);

    /// @dev Thrown when there is no tokens to rescue
    error EmptyBalance();

    /// @dev Thrown when the caller is not the router
    error OnlyRouter();

    /// @dev Thrown when caller is not the leverage user
    error OnlyLeverageUser();

    /// @dev Thrown when native token transfer fails
    error NativeTokenTransferFailed();

    constructor() {
        TOKEN_RECEIVER = msg.sender;
    }

    function rescueNativeTokens() external {
        uint256 balance = address(this).balance;
        require(balance != 0, EmptyBalance());

        (bool success, ) = payable(TOKEN_RECEIVER).call{value: balance}("");
        require(success, NativeTokenTransferFailed());

        emit TokensRescued(address(0), balance);
    }

    function rescueTokens(IERC20 _token) external {
        uint256 balance = _token.balanceOf(address(this));
        require(balance != 0, EmptyBalance());

        _token.safeTransfer(TOKEN_RECEIVER, balance);
        emit TokensRescued(address(_token), balance);
    }
}
