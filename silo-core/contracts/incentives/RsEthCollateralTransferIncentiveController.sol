// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SiloIncentivesControllerCompatible} from "./SiloIncentivesControllerCompatible.sol";

contract RsEthCollateralTransferIncentiveController is SiloIncentivesControllerCompatible {
    constructor(address _owner, address _notifier, address _shareTokenAddress) 
        SiloIncentivesControllerCompatible(_owner, _notifier, _shareTokenAddress)
    {
    }
}
