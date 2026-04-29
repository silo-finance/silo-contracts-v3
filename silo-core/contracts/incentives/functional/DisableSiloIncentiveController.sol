// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SiloIncentivesControllerCompatible} from "../SiloIncentivesControllerCompatible.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

/// @notice you can completely disable empty Silo, if you will set this incentive controller.
contract DisableSiloIncentiveController is SiloIncentivesControllerCompatible {
    error SiloDisabled();

    constructor(address _owner, address _notifier, address _shareTokenAddress)
        SiloIncentivesControllerCompatible(_owner, _notifier, _shareTokenAddress)
    {}

    /// @dev this incentive controller needs to be set for protected and collateral
    function afterTokenTransfer(
        address /*_sender*/,
        uint256 /*_senderBalance*/,
        address /*_recipient*/,
        uint256 /*_recipientBalance*/,
        uint256 /*_totalSupply*/,
        uint256 /*_amount*/
    )
        public
        virtual
        override
    {
        // we can disable only when empty
        uint256 totalSupply = IShareToken(msg.sender).totalSupply();

        // If by mistake anyone would set this incentive controller to non-empty silo, then it will not revert on non empty share
        // In that case, we can simply exit the silo because we can withdraw, repay, and liquidate 
        // because these will be operations on a non-empty share token.
        if (totalSupply > 0) revert SiloDisabled();
    }
}
