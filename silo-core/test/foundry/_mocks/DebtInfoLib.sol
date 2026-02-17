// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

library DebtInfoLib {
    function debtInThisSilo(ISiloConfig.ConfigData memory _debtConfig, address _silo)
        internal
        pure
        returns (bool)
    {
        return _debtConfig.silo == _silo;
    }

    function debtPresent(ISiloConfig.ConfigData memory _debtConfig) internal pure returns (bool debtStatus) {
        debtStatus = _debtConfig.silo != address(0);
    }
}
