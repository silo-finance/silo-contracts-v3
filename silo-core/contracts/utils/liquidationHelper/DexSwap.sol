// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {RevertLib} from "../../lib/RevertLib.sol";

/// @dev Based on demo contract that swaps its ERC20 balance for another ERC20.
/// demo source: https://github.com/0xProject/0x-api-starter-guide-code/blob/master/contracts/SimpleTokenSwap.sol
contract DexSwap {
    using RevertLib for bytes;

    /// @dev 0x ExchangeProxy address.
    /// See https://docs.0x.org/developer-resources/contract-addresses
    /// The `to` field from the API response, but at the same time,
    // solhint-disable-next-line var-name-mixedcase
    address public immutable EXCHANGE_PROXY;

    error AddressZero();

    constructor(address _exchangeProxy) {
        if (_exchangeProxy == address(0)) revert AddressZero();

        EXCHANGE_PROXY = _exchangeProxy;
    }

    /// @dev Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
    /// @param _sellToken The `sellTokenAddress` field from the API response.
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    function fillQuote(address _sellToken, address _spender, bytes memory _swapCallData) public virtual {
        IERC20(_sellToken).approve(_spender, type(uint256).max);

        // Call the encoded swap function call on the contract at `swapTarget`
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = EXCHANGE_PROXY.call(_swapCallData);
        if (!success) data.revertBytes("SWAP_CALL_FAILED");

        IERC20(_sellToken).approve(_spender, 0);
    }
}
