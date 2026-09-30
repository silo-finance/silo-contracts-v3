// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MintableToken} from "../../_common/MintableToken.sol";

contract SwapRouterMock {
    using SafeERC20 for IERC20;

    address sellToken;
    address buyToken;
    uint256 public amountIn;
    uint256 public amountOut;

    function setSwap(address _sellToken, uint256 _amountIn, address _buyToken, uint256 _amountOut) external {
        sellToken = _sellToken;
        buyToken = _buyToken;

        amountIn = _amountIn;
        amountOut = _amountOut;
    }

    fallback() external {
        if (amountIn != 0) IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);
        if (amountOut != 0) MintableToken(buyToken).mint(msg.sender, amountOut);
    }
}
