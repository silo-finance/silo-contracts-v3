// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RevertLib} from "../../lib/RevertLib.sol";
import {IGeneralSwapModule} from "../../interfaces/IGeneralSwapModule.sol";
import {TransientReentrancy} from "../../hooks/_common/TransientReentrancy.sol";

/// @title ERC20 General use Swap Module
/// @notice Enables ERC20 token swaps via an external exchange (e.g., 0x, ODOS, Pendle)
/// @dev Based on the 0x demo contract:
/// https://github.com/0xProject/0x-api-starter-guide-code/blob/master/contracts/SimpleTokenSwap.sol
/// The swap module is designed to execute external calls and is under the caller's full control.
/// It can call any contract using any method. NEVER approve any tokens for it!
contract GeneralSwapModule is TransientReentrancy, IGeneralSwapModule {
    using SafeERC20 for IERC20;

    /// @notice Executes a token swap using a prebuilt swap quote
    /// @dev The contract must hold the sell token balance before calling.
    /// @param _swapArgs SwapArgs struct containing all parameters for executing a swap
    /// @param _maxApprovalAmount Amount of sell token to approve before the swap
    /// @return amountOut Amount of buy token received after the swap including any previous balance that contract has
    function fillQuote(SwapArgs memory _swapArgs, uint256 _maxApprovalAmount)
        external
        virtual
        nonReentrant
        returns (uint256 amountOut)
    {
        if (_swapArgs.exchangeProxy == address(0)) revert ExchangeAddressZero();

        // Approve token for spending by the exchange
        IERC20(_swapArgs.sellToken).forceApprove(_swapArgs.allowanceTarget, _maxApprovalAmount);

        // Perform low-level call to any method and any smart contract provided by the caller.
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = _swapArgs.exchangeProxy.call(_swapArgs.swapCallData);
        if (!success) RevertLib.revertBytes(data, SwapCallFailed.selector);

        amountOut = _transferBalanceToSender(_swapArgs.buyToken);
        if (amountOut == 0) revert ZeroAmountOut();

        _transferBalanceToSender(_swapArgs.sellToken);
    }

    function _transferBalanceToSender(address _token) internal virtual returns (uint256 balance) {
        balance = IERC20(_token).balanceOf(address(this));

        if (balance != 0) {
            IERC20(_token).safeTransfer(msg.sender, balance);
        }
    }
}
