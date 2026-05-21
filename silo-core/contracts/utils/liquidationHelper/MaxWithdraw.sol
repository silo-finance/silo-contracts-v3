// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626 } from "openzeppelin5/interfaces/IERC4626.sol";
import { RescueTokens } from "../RescueTokens.sol";

contract MaxWithdraw is RescueTokens {
    /// @dev it requires approval on the silo collateral token, it allowes to do maximum withdraw
    function doMaxWithdraw(IERC4626 _silo) external {
        address owner = msg.sender;
        
        _silo.redeem({
            shares: _silo.maxRedeem(owner),
            receiver: owner,
            owner: owner
        });
    }
}
