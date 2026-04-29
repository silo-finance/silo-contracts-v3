// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ISiloIncentivesController} from "../interfaces/ISiloIncentivesController.sol";
import {IBackwardsCompatibleGaugeLike} from "./interfaces/IBackwardsCompatibleGaugeLike.sol";

abstract contract BaseIncentivesControllerCompatible is IBackwardsCompatibleGaugeLike, ISiloIncentivesController {
    /// @notice Whether the gauge is killed
    /// @dev This flag is not used in the SiloIncentivesController,
    /// but it is used in the Gauge hook receiver (versions <= 3.7.0).
    bool internal _isKilled;

    event GaugeKilled();
    event GaugeUnKilled();

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function killGauge() external virtual onlyOwner {
        _isKilled = true;
        emit GaugeKilled();
    }

    function unkillGauge() external virtual onlyOwner {
        _isKilled = false;
        emit GaugeUnKilled();
    }

    // solhint-disable-next-line func-name-mixedcase
    function share_token() external view returns (address) {
        return SHARE_TOKEN;
    }

    // solhint-disable-next-line func-name-mixedcase
    function is_killed() external view returns (bool) {
        return _isKilled;
    }

    function _onlyOwner() internal view virtual;
}
