// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISilo} from "../interfaces/ISilo.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {ISiloConfig} from "../interfaces/ISiloConfig.sol";

import {ShareTokenLib} from "./ShareTokenLib.sol";
import {CallBeforeQuoteLib} from "./CallBeforeQuoteLib.sol";
import {SiloSolvencyLib} from "./SiloSolvencyLib.sol";

library ShareCollateralTokenLib {
    using CallBeforeQuoteLib for ISiloConfig.ConfigData;

    function isSolventAfterCollateralTransfer(address _sender) external returns (bool isSolvent) {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();
        ISiloConfig siloConfig = $.siloConfig;

        (
            ISiloConfig.DepositConfig memory deposit,
            ISiloConfig.ConfigData memory collateral,
            ISiloConfig.ConfigData memory debt
        ) = siloConfig.getConfigsForWithdraw(address($.silo), _sender);

        // when deposit silo is collateral silo, that means this sToken is collateral for debt
        if (collateral.silo != deposit.silo) return true;

        siloConfig.accrueInterestForBothSilos();

        ShareTokenLib.callOracleBeforeQuote(siloConfig, _sender);

        isSolvent = SiloSolvencyLib.isSolvent(collateral, debt, _sender, ISilo.AccrueInterestInMemory.No);
    }
}
