// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Logger} from "silo-core/deploy/silo/verifier/Logger.sol";

import {ICheck} from "silo-core/deploy/silo/verifier/checks/ICheck.sol";
import {CheckDaoFee} from "silo-core/deploy/silo/verifier/checks/silo/CheckDaoFee.sol";
import {CheckDeployerFee} from "silo-core/deploy/silo/verifier/checks/silo/CheckDeployerFee.sol";
import {CheckLiquidationFee} from "silo-core/deploy/silo/verifier/checks/silo/CheckLiquidationFee.sol";
import {CheckPTLinearOracle} from "silo-core/deploy/silo/verifier/checks/silo/CheckPTLinearOracle.sol";
import {CheckFlashloanFee} from "silo-core/deploy/silo/verifier/checks/silo/CheckFlashloanFee.sol";
import {CheckIrmConfig} from "silo-core/deploy/silo/verifier/checks/silo/CheckIrmConfig.sol";
import {CheckMaxLtvLtLiquidationFee} from "silo-core/deploy/silo/verifier/checks/silo/CheckMaxLtvLtLiquidationFee.sol";
import {CheckNonBorrowableAsset} from "silo-core/deploy/silo/verifier/checks/silo/CheckNonBorrowableAsset.sol";
import {CheckHookOwner} from "silo-core/deploy/silo/verifier/checks/silo/CheckHookOwner.sol";
import {CheckIrmOwner} from "silo-core/deploy/silo/verifier/checks/silo/CheckIrmOwner.sol";
import {CheckOracleOwner} from "silo-core/deploy/silo/verifier/checks/silo/CheckOracleOwner.sol";
import {CheckIncentivesOwner} from "silo-core/deploy/silo/verifier/checks/silo/CheckIncentivesOwner.sol";
import {CheckIncentivesForDefaulting} from "silo-core/deploy/silo/verifier/checks/silo/CheckIncentivesForDefaulting.sol";
import {CheckShareTokensInGauge} from "silo-core/deploy/silo/verifier/checks/silo/CheckShareTokensInGauge.sol";
import {CheckSiloImplementation} from "silo-core/deploy/silo/verifier/checks/silo/CheckSiloImplementation.sol";
import {CheckSiloFactory} from "silo-core/deploy/silo/verifier/checks/silo/CheckSiloFactory.sol";

import {CheckPriceDoesNotReturnZero} from
    "silo-core/deploy/silo/verifier/checks/behavior/CheckPriceDoesNotReturnZero.sol";
import {CheckQuoteIsLinearFunction} from
    "silo-core/deploy/silo/verifier/checks/behavior/CheckQuoteIsLinearFunction.sol";
import {CheckQuoteLargeAmounts} from "silo-core/deploy/silo/verifier/checks/behavior/CheckQuoteLargeAmounts.sol";
import {CheckExternalPrices} from "silo-core/deploy/silo/verifier/checks/behavior/CheckExternalPrices.sol";

contract SiloVerifier {
    ISiloConfig public immutable SILO_CONFIG;
    bool public immutable LOG_DETAILS;
    Logger public immutable LOGGER;

    uint256 public immutable EXTERNAL_PRICE_0;
    uint256 public immutable EXTERNAL_PRICE_1;

    ICheck[] internal _checks;

    constructor(ISiloConfig _siloConfig, bool _logDetails, uint256 _externalPrice0, uint256 _externalPrice1) {
        SILO_CONFIG = _siloConfig;
        LOG_DETAILS = _logDetails;
        EXTERNAL_PRICE_0 = _externalPrice0;
        EXTERNAL_PRICE_1 = _externalPrice1;
        LOGGER = new Logger();

        _buildChecks(_siloConfig);
    }

    function verify() external returns (uint256 errorsCounter) {
        if (LOG_DETAILS) {
            LOGGER.logSetup(SILO_CONFIG);

            console2.log("Total checks:", _checks.length);
        }

        for (uint256 i; i < _checks.length; i++) {
            bool success = _checks[i].execute();

            if (!success) {
                errorsCounter++;
                console2.log(LOGGER.FAIL_SYMBOL(), _checks[i].checkName(), ":", _checks[i].errorMessage());
            } else {
                console2.log(LOGGER.SUCCESS_SYMBOL(), _checks[i].checkName(), ":", _checks[i].successMessage());
            }
        }

        if (errorsCounter == 0) {
            console2.log(LOGGER.SUCCESS_SYMBOL(), "all checks passed with 0 errors");
        } else {
            console2.log(LOGGER.FAIL_SYMBOL(), "checks failed with", errorsCounter, "errors");
        }
    }

    function _buildChecks(ISiloConfig _siloConfig) internal {
        (address silo0, address silo1) = _siloConfig.getSilos();
        ISiloConfig.ConfigData memory configData0 = _siloConfig.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = _siloConfig.getConfig(silo1);

        _buildSiloStateChecks(configData0, true);
        _buildSiloStateChecks(configData1, false);

        _checks.push(new CheckNonBorrowableAsset(configData0.token, configData1));

        _buildBehaviorChecks(configData0, configData1);
    }

    function _buildSiloStateChecks(ISiloConfig.ConfigData memory _configData, bool _isSiloZero) internal {
        _checks.push(new CheckSiloFactory(_configData, _isSiloZero));
        _checks.push(new CheckDaoFee(_configData, _isSiloZero));
        _checks.push(new CheckDeployerFee(_configData, _isSiloZero));
        _checks.push(new CheckLiquidationFee(_configData, _isSiloZero));
        _checks.push(new CheckFlashloanFee(_configData, _isSiloZero));
        _checks.push(new CheckIrmConfig(_configData, _isSiloZero));
        _checks.push(new CheckIrmOwner(_configData, _isSiloZero));
        _checks.push(new CheckOracleOwner(_configData, _isSiloZero));
        _checks.push(new CheckMaxLtvLtLiquidationFee(_configData, _isSiloZero));
        _checks.push(new CheckHookOwner(_configData, _isSiloZero));
        _checks.push(new CheckIncentivesOwner(_configData, _isSiloZero));
        _checks.push(new CheckIncentivesForDefaulting(_configData, _isSiloZero));
        _checks.push(new CheckShareTokensInGauge(_configData, _isSiloZero));
        _checks.push(new CheckSiloImplementation(_configData, _isSiloZero));
        _checks.push(new CheckPTLinearOracle(_configData.solvencyOracle, _configData.token));
    }

    function _buildBehaviorChecks(
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) internal {
        if (_configData0.solvencyOracle != address(0)) {
            _buildSingleOracleChecks(_configData0.solvencyOracle, _configData0.token, "solvencyOracle0");
        }

        if (_configData0.maxLtvOracle != address(0) && _configData0.maxLtvOracle != _configData0.solvencyOracle) {
            _buildSingleOracleChecks(_configData0.maxLtvOracle, _configData0.token, "maxLtvOracle0");
        }

        if (_configData1.solvencyOracle != address(0)) {
            _buildSingleOracleChecks(_configData1.solvencyOracle, _configData1.token, "solvencyOracle1");
        }

        if (_configData1.maxLtvOracle != address(0) && _configData1.maxLtvOracle != _configData1.solvencyOracle) {
            _buildSingleOracleChecks(_configData1.maxLtvOracle, _configData1.token, "maxLtvOracle1");
        }

        _checks.push(
            new CheckExternalPrices({
                _solvencyOracle0: _configData0.solvencyOracle,
                _token0: _configData0.token,
                _externalPrice0: EXTERNAL_PRICE_0,
                _solvencyOracle1: _configData1.solvencyOracle,
                _token1: _configData1.token,
                _externalPrice1: EXTERNAL_PRICE_1
            })
        );
    }

    function _buildSingleOracleChecks(address _oracle, address _token, string memory _oracleName) internal {
        _checks.push(new CheckPriceDoesNotReturnZero(_oracle, _token, _oracleName));

        _checks.push(new CheckQuoteIsLinearFunction(_oracle, _token, _oracleName));

        _checks.push(new CheckQuoteLargeAmounts(_oracle, _token, _oracleName));
    }
}
