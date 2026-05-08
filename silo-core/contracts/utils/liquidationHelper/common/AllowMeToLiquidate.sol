// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISiloIncentivesController} from "../../../incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "../../../interfaces/IGaugeHookReceiver.sol";
import {IPermissionedLiquidationController} from "../../../interfaces/IPermissionedLiquidationController.sol";
import {IShareToken} from "../../../interfaces/IShareToken.sol";

abstract contract AllowMeToLiquidate {
    function _allowMeToLiquidate(address _hookReceiver, IShareToken _shareToken) internal virtual {
        ISiloIncentivesController controller = IGaugeHookReceiver(_hookReceiver).configuredGauges(_shareToken);
        if (address(controller) == address(0)) return;
        
        try IPermissionedLiquidationController(address(controller)).allowMeToLiquidate() {
            // allowed
        } catch {
            // not allwoed or not supported
        }
    }
}
