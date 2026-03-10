// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {InterestRateModelConfigData} from "silo-core/deploy/input-readers/InterestRateModelConfigData.sol";
import {
    InterestRateModelV2, IInterestRateModelV2
} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interfaces/IInterestRateModelV2Config.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {ChainlinkV3OracleConfig} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3OracleConfig.sol";
import {IChainlinkV3Oracle} from "silo-oracles/contracts/interfaces/IChainlinkV3Oracle.sol";
import {ChainlinkV3Oracle} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3Oracle.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {Utils, IPTLinearAggregatorLike} from "silo-core/deploy/silo/verifier/Utils.sol";
import {PendlePTOracle} from "silo-oracles/contracts/pendle/PendlePTOracle.sol";
import {PendleLPTOracle} from "silo-oracles/contracts/pendle/lp-tokens/PendleLPTOracle.sol";
import {PendlePTToAssetOracle} from "silo-oracles/contracts/pendle/PendlePTToAssetOracle.sol";

import {IDIAOracle, DIAOracle, DIAOracleConfig} from "silo-oracles/contracts/dia/DIAOracle.sol";
import {
    WrappedMetaVaultOracleAdapter,
    IWrappedMetaVaultOracle
} from "silo-oracles/contracts/custom/wrappedMetaVaultOracle/WrappedMetaVaultOracleAdapter.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";
import {PTLinearOracle} from "silo-oracles/contracts/pendle/linear/PTLinearOracle.sol";

contract Logger is Test {
    // used to generate quote amounts and names to log
    struct QuoteNamedAmount {
        uint256 amount;
        string name;
        bool logExponentialNotation; // will log 1e123 instead of 1000...0000
        bool quoteForOneToken; // if we checking price for one token (10 ^ decimals)
    }

    struct OldChainlinkV3Config {
        AggregatorV3Interface primaryAggregator;
        AggregatorV3Interface secondaryAggregator;
        uint256 primaryHeartbeat;
        uint256 secondaryHeartbeat;
        uint256 normalizationDivider;
        uint256 normalizationMultiplier;
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        bool convertToQuote;
    }

    string public constant SUCCESS_SYMBOL = unicode"✅";
    string public constant FAIL_SYMBOL = unicode"❌";
    string public constant WARNING_SYMBOL = unicode"🚨";

    string public constant DELIMITER =
        "\n----------------------------------------------------------------------------";

    uint256 internal constant _OLD_CHAINLINK_CONFIG_DATA_LEN = 288;
    uint256 internal constant _NEW_CHAINLINK_CONFIG_DATA_LEN = 320;
    uint256 internal constant _DIA_CONFIG_DATA_LEN = 256;

    /// @dev this function must log all details about Silo setup, including current spot prices. This information
    /// must be enough to review the Silo deployment configuration and oracles setup.
    function logSetup(ISiloConfig _siloConfig) external {
        console2.log(DELIMITER);

        _logSiloSetup({_siloConfig: _siloConfig, _forSiloZero: true});

        console2.log(DELIMITER);

        _logSiloSetup({_siloConfig: _siloConfig, _forSiloZero: false});

        console2.log(DELIMITER);

        _logOracles(_siloConfig);
    }

    function _logSiloSetup(ISiloConfig _siloConfig, bool _forSiloZero) internal {
        ISiloConfig.ConfigData memory configData;
        address silo;

        if (_forSiloZero) {
            (silo,) = _siloConfig.getSilos();
        } else {
            (, silo) = _siloConfig.getSilos();
        }

        configData = ISiloConfig(_siloConfig).getConfig(silo);

        emit log_string(_forSiloZero ? "silo0" : "silo1");
        emit log_named_address("\tsilo                    ", silo);
        emit log_named_address("\ttoken                   ", configData.token);
        emit log_named_string("\tsymbol                  ", Utils.tryGetTokenSymbol(configData.token));
        emit log_named_uint("\tdecimals                ", Utils.tryGetTokenDecimals(configData.token));
        emit log_named_decimal_uint("\tdaoFee(%)               ", configData.daoFee * 100, 18);
        emit log_named_decimal_uint("\tdeployerFee(%)          ", configData.deployerFee * 100, 18);
        emit log_named_decimal_uint("\tliquidationFee(%)       ", configData.liquidationFee * 100, 18);
        emit log_named_decimal_uint("\tflashloanFee(%)         ", configData.flashloanFee * 100, 18);
        emit log_named_decimal_uint("\tmaxLtv(%)               ", configData.maxLtv * 100, 18);
        emit log_named_decimal_uint("\tlt(%)                   ", configData.lt * 100, 18);
        emit log_named_decimal_uint("\tliquidationTargetLtv(%) ", configData.liquidationTargetLtv * 100, 18);
        emit log_named_address("\tsolvencyOracle          ", configData.solvencyOracle);
        emit log_named_address("\tmaxLtvOracle            ", configData.maxLtvOracle);
        emit log_named_address("\tinterestRateModel       ", configData.interestRateModel);

        console2.log();
        (string memory irmName, bool success) = Utils.findIrmName(configData);

        if (success) {
            console2.log("\tIRM is", irmName);
        } else {
            console2.log(string.concat("\t", WARNING_SYMBOL, "IRM setup is not known"));
        }

        console2.log();
        _logIncentivesSetup(configData, IShareToken(configData.protectedShareToken));
        _logIncentivesSetup(configData, IShareToken(configData.collateralShareToken));
        _logIncentivesSetup(configData, IShareToken(configData.debtShareToken));
    }

    function _logIncentivesSetup(ISiloConfig.ConfigData memory _configData, IShareToken _shareToken) internal view {
        GaugeHookReceiver hookReceiver = GaugeHookReceiver(_configData.hookReceiver);
        string memory shareTokenName = Utils.tryGetTokenSymbol(address(_shareToken));

        if (address(hookReceiver.configuredGauges(_shareToken)) != address(0)) {
            console2.log("\tIncentives are configured for", shareTokenName);
        } else {
            console2.log("\tNo incentives for", shareTokenName);
        }
    }

    function _logOracles(ISiloConfig _siloConfig) internal {
        (address silo0, address silo1) = _siloConfig.getSilos();
        ISiloConfig.ConfigData memory configData0 = ISiloConfig(_siloConfig).getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = ISiloConfig(_siloConfig).getConfig(silo1);

        if (configData0.solvencyOracle != address(0)) {
            _logOracle(ISiloOracle(configData0.solvencyOracle), configData0.token);
        } else {
            uint256 tokenDecimals = Utils.tryGetTokenDecimals(configData0.token);
            string memory price = PriceFormatter.formatPriceInE18(10 ** tokenDecimals);
            console2.log("\n\tOracle is not set for silo0, price will be: ", price, "\n", DELIMITER);
        }

        if (configData0.maxLtvOracle != configData0.solvencyOracle && configData0.maxLtvOracle != address(0)) {
            _logOracle(ISiloOracle(configData0.maxLtvOracle), configData0.token);
        }

        if (configData1.solvencyOracle != address(0)) {
            _logOracle(ISiloOracle(configData1.solvencyOracle), configData1.token);
        } else {
            uint256 tokenDecimals = Utils.tryGetTokenDecimals(configData1.token);
            string memory price = PriceFormatter.formatPriceInE18(10 ** tokenDecimals);
            console2.log("\n\tOracle is not set for silo1, price will be: ", price, "\n", DELIMITER);
        }

        if (configData1.maxLtvOracle != configData1.solvencyOracle && configData1.maxLtvOracle != address(0)) {
            _logOracle(ISiloOracle(configData1.maxLtvOracle), configData1.token);
        }
    }

    function _logOracle(ISiloOracle _oracle, address _baseToken) internal {
        bool isManageableOracle = Utils.isManageableOracle(address(_oracle));

        if (!isManageableOracle) {
            console2.log("\t", WARNING_SYMBOL, "Oracle is not a ManageableOracle");
        } else {
            console2.log("\t", SUCCESS_SYMBOL, "Oracle is manageable");
            _oracle = IManageableOracle(address(_oracle)).oracle();
        }

        address quoteToken = _oracle.quoteToken();
        uint8 baseTokenDecimals = Utils.tryGetTokenDecimals(_baseToken);

        (bool success, uint256 oneTokenPrice) = Utils.quote(_oracle, _baseToken, 10 ** uint256(baseTokenDecimals));

        string memory oneTokenPriceLogMessage = string.concat(
            "\tPrice of one token (in it's own decimals, ",
            Utils.tryGetTokenSymbol(_baseToken),
            " decimals=",
            Strings.toString(baseTokenDecimals),
            ") normalized by 18 decimals"
        );

        if (!success) {
            revert("Unable to quote one token in it's own decimals");
        }

        console2.log("\nOracle:", address(_oracle));
        console2.log("\tToken name:", Utils.tryGetTokenSymbol(_baseToken));
        console2.log("\tToken symbol:", Utils.tryGetTokenSymbol(_baseToken));
        console2.log("\tToken decimals:", baseTokenDecimals);
        emit log_named_decimal_uint(oneTokenPriceLogMessage, oneTokenPrice, 18);
        console2.log();
        console2.log("\tQuote token name:", Utils.tryGetTokenSymbol(quoteToken));
        console2.log("\tQuote token symbol:", Utils.tryGetTokenSymbol(quoteToken));
        console2.log("\tQuote token decimals:", Utils.tryGetTokenDecimals(quoteToken));
        console2.log("\tQuote token:", quoteToken);

        try PendlePTOracle(address(_oracle)).MARKET() returns (address market) {
            _logPendleOracle(_oracle, market, false);
        } catch {}

        try PTLinearOracle(address(_oracle)).baseDiscountPerYear() returns (uint256) {
            _logPendleLinearOracle(_oracle);
        } catch {}

        try PendleLPTOracle(address(_oracle)).PENDLE_MARKET() returns (address market) {
            _logPendleOracle(_oracle, market, true);
        } catch {}

        (address primaryAggregator, address secondaryAggregator) =
            _resolveUnderlyingChainlinkAggregators({_oracle: _oracle, _logDetails: false});

        if (primaryAggregator != address(0)) {
            _logLatestRoundData({_aggregator: primaryAggregator, _isPrimary: true});
        }

        if (secondaryAggregator != address(0)) {
            _logLatestRoundData({_aggregator: secondaryAggregator, _isPrimary: false});
        }

        console2.log("\n\tQuotes for different amounts:");
        QuoteNamedAmount[] memory amountsToQuote = _getAmountsToQuote(baseTokenDecimals);

        for (uint256 i; i < amountsToQuote.length; i++) {
            _printPrice(_oracle, _baseToken, amountsToQuote[i]);
        }

        _resolveUnderlyingChainlinkAggregators({_oracle: _oracle, _logDetails: true});

        console2.log(DELIMITER);
    }

    function _logPendleOracle(ISiloOracle _oracle, address market, bool isLPTWrapper) internal {
        console2.log(DELIMITER);
        console2.log("\n\tPENDLE ORACLE INFO\n");
        console2.log("\tMarket:", market);

        console2.log(
            "\tPendle oracle (Pendle protocol deployments):",
            address(PendlePTOracle(address(_oracle)).PENDLE_ORACLE())
        );

        if (!isLPTWrapper) {
            address ptToken = address(PendlePTOracle(address(_oracle)).PT_TOKEN());
            console2.log("\tPT token:", ptToken);
            console2.log("\tPT token symbol:", IERC20Metadata(ptToken).symbol());
        }

        address underlyingToken;

        try PendlePTToAssetOracle(address(_oracle)).SY_UNDERLYING_TOKEN() returns (address syUnderlyingToken) {
            console2.log("\tSY underlying token:", syUnderlyingToken);
            underlyingToken = syUnderlyingToken;
        } catch {}

        try PendlePTOracle(address(_oracle)).PT_UNDERLYING_TOKEN() returns (address ptUnderlyingToken) {
            console2.log("\tPT underlying token:", ptUnderlyingToken);
            underlyingToken = ptUnderlyingToken;
        } catch {}

        try PendleLPTOracle(address(_oracle)).UNDERLYING_TOKEN() returns (address lptUnderlyingToken) {
            console2.log("\tLPT underlying token:", lptUnderlyingToken);
            underlyingToken = lptUnderlyingToken;
        } catch {}

        address underlyingOracle = address(PendlePTOracle(address(_oracle)).UNDERLYING_ORACLE());
        console2.log("\tUnderlying token symbol:", IERC20Metadata(underlyingToken).symbol());
        console2.log("\tUnderlying oracle:", underlyingOracle);
        console2.log("\n\tPendle underlying oracle info:");
        _logOracle(ISiloOracle(underlyingOracle), underlyingToken);
        console2.log(DELIMITER);
    }

    function _logPendleLinearOracle(ISiloOracle _oracle) internal view {
        console2.log(DELIMITER);
        console2.log("\n\tPENDLE LINEAR ORACLE INFO\n");
        console2.log("\tdescription:", PTLinearOracle(address(_oracle)).description());
        console2.log(
            "\tbaseDiscountPerYear:",
            PriceFormatter.formatPriceInE18(PTLinearOracle(address(_oracle)).baseDiscountPerYear())
        );
        console2.log(DELIMITER);
    }

    function _logLatestRoundData(address _aggregator, bool _isPrimary) internal {
        string memory aggregatorType = _isPrimary ? "Primary" : "Secondary";
        uint8 aggregatorDecimals = AggregatorV3Interface(_aggregator).decimals();

        string memory latestRoundDataLogMessage = string.concat(
            "\n\t",
            aggregatorType,
            " aggregator latestRoundData normalized by own decimals (",
            Strings.toString(uint256(aggregatorDecimals)),
            ")"
        );

        (
            /*uint80 roundID*/
            ,
            int256 aggregatorPrice,
            /*uint256 startedAt*/
            ,
            uint256 priceTimestamp,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(_aggregator).latestRoundData();

        emit log_named_decimal_uint(latestRoundDataLogMessage, uint256(aggregatorPrice), aggregatorDecimals);

        console2.log(
            "\tPrice update was",
            Utils.timestampFromNowDescription(priceTimestamp),
            "from now, update timestamp is",
            priceTimestamp
        );
    }

    /// @dev returns underlying primary and secondary aggregators. Logs setup if needed.
    function _resolveUnderlyingChainlinkAggregators(ISiloOracle _oracle, bool _logDetails)
        internal
        view
        returns (address primaryAggregator, address secondaryAggregator)
    {
        try ChainlinkV3Oracle(address(_oracle)).oracleConfig() returns (ChainlinkV3OracleConfig oracleConfig) {
            (, bytes memory data) =
                address(oracleConfig).staticcall(abi.encodeWithSelector(ChainlinkV3OracleConfig.getConfig.selector));

            if (data.length == _OLD_CHAINLINK_CONFIG_DATA_LEN) {
                OldChainlinkV3Config memory config = abi.decode(data, (OldChainlinkV3Config));

                if (_logDetails) {
                    _printChainlinkOracleDetails({
                        _oracleConfig: address(oracleConfig),
                        _primaryAggregator: address(config.primaryAggregator),
                        _secondaryAggregator: address(config.secondaryAggregator),
                        _primaryHeartbeat: config.primaryHeartbeat,
                        _secondaryHeartbeat: config.secondaryHeartbeat,
                        _normalizationDivider: config.normalizationDivider,
                        _normalizationMultiplier: config.normalizationMultiplier,
                        _convertToQuote: config.convertToQuote,
                        _invertSecondPrice: false
                    });
                }

                primaryAggregator = address(config.primaryAggregator);
                secondaryAggregator = address(config.secondaryAggregator);
            } else if (data.length == _NEW_CHAINLINK_CONFIG_DATA_LEN) {
                IChainlinkV3Oracle.ChainlinkV3Config memory config =
                    abi.decode(data, (IChainlinkV3Oracle.ChainlinkV3Config));

                if (_logDetails) {
                    _printChainlinkOracleDetails({
                        _oracleConfig: address(oracleConfig),
                        _primaryAggregator: address(config.primaryAggregator),
                        _secondaryAggregator: address(config.secondaryAggregator),
                        _primaryHeartbeat: config.primaryHeartbeat,
                        _secondaryHeartbeat: config.secondaryHeartbeat,
                        _normalizationDivider: config.normalizationDivider,
                        _normalizationMultiplier: config.normalizationMultiplier,
                        _convertToQuote: config.convertToQuote,
                        _invertSecondPrice: config.invertSecondPrice
                    });
                }

                primaryAggregator = address(config.primaryAggregator);
                secondaryAggregator = address(config.secondaryAggregator);
            } else if (data.length == _DIA_CONFIG_DATA_LEN) {
                IDIAOracle.DIAConfig memory config = abi.decode(data, (IDIAOracle.DIAConfig));

                string memory primaryKey =
                    DIAOracle(address(_oracle)).primaryKey(DIAOracleConfig(address(oracleConfig)));

                string memory secondaryKey =
                    DIAOracle(address(_oracle)).secondaryKey(DIAOracleConfig(address(oracleConfig)));

                if (_logDetails) {
                    _printDiaOracleDetails({
                        _primaryKey: primaryKey,
                        _secondaryKey: secondaryKey,
                        _diaSourceFeed: address(config.diaOracle),
                        _heartbeat: config.heartbeat,
                        _normalizationDivider: config.normalizationDivider,
                        _normalizationMultiplier: config.normalizationMultiplier,
                        _convertToQuote: config.convertToQuote,
                        _invertSecondPrice: config.invertSecondPrice
                    });
                }
            } else {
                console2.log(WARNING_SYMBOL, "can't recognize Chainlink/DIA config: invalid return data len");
            }
        } catch {
            console2.log(WARNING_SYMBOL, "Oracle does not have a ChainlinkV3OracleConfig, may be expected");
        }
    }

    function _printDiaOracleDetails(
        string memory _primaryKey,
        string memory _secondaryKey,
        address _diaSourceFeed,
        uint32 _heartbeat,
        uint256 _normalizationDivider,
        uint256 _normalizationMultiplier,
        bool _convertToQuote,
        bool _invertSecondPrice
    ) internal pure {
        console2.log("\nDIA underlying feed setup:");
        console2.log("\tPrimary key: ", _primaryKey);

        if (!Strings.equal(_secondaryKey, "")) {
            console2.log("\tSecondary key: ", _secondaryKey);
        }

        console2.log("\tHeartbeat: ", _heartbeat);
        console2.log("\tNormalization multiplier: ", _normalizationMultiplier);
        console2.log("\tNormalization divider: ", _normalizationDivider);
        console2.log("\tConvert to quote: ", _convertToQuote);
        console2.log("\tInvert second price: ", _invertSecondPrice);
        console2.log("\tDIA source feed address: ", _diaSourceFeed);

        if (Strings.equal(_secondaryKey, "\"\"")) {
            console2.log(FAIL_SYMBOL, "secondary feed is string with quotes \"\"");
        }
    }

    function _printChainlinkOracleDetails(
        address _oracleConfig,
        address _primaryAggregator,
        address _secondaryAggregator,
        uint256 _primaryHeartbeat,
        uint256 _secondaryHeartbeat,
        uint256 _normalizationDivider,
        uint256 _normalizationMultiplier,
        bool _convertToQuote,
        bool _invertSecondPrice
    ) internal view {
        console2.log("\n\tChainlinkV3 underlying feed setup:");
        console2.log("\tOracle config: ", _oracleConfig);
        console2.log("\tPrimary aggregator: ", _primaryAggregator);
        console2.log("\tPrimary aggregator name: ", Utils.tryGetAggregatorDescription(_primaryAggregator));
        _tryLogPTLinearAggregator(_primaryAggregator);
        console2.log("\tPrimary aggregator decimals: ", AggregatorV3Interface(_primaryAggregator).decimals());
        console2.log("\tSecondary aggregator: ", _secondaryAggregator);

        if (_secondaryAggregator != address(0)) {
            console2.log("\tSecondary aggregator name: ", Utils.tryGetAggregatorDescription(_secondaryAggregator));
            console2.log("\tSecondary aggregator decimals: ", AggregatorV3Interface(_secondaryAggregator).decimals());
            _tryLogPTLinearAggregator(_primaryAggregator);
        }

        console2.log("\tPrimary heartbeat: ", _primaryHeartbeat);
        console2.log("\tSecondary heartbeat: ", _secondaryHeartbeat);
        console2.log("\tNormalization divider: ", _normalizationDivider);
        console2.log("\tNormalization multiplier: ", _normalizationMultiplier);
        console2.log("\tConvert to quote: ", _convertToQuote);
        console2.log("\tInvert second price: ", _invertSecondPrice);

        try WrappedMetaVaultOracleAdapter(address(_primaryAggregator)).FEED() returns (IWrappedMetaVaultOracle feed) {
            console2.log("\tUnderlying WrappedMetaVaultOracle: ", address(feed));
            console2.log("\tUnderlying wrappedMetaVault: ", address(feed.wrappedMetaVault()));
        } catch {}
    }

    // TODO add option for trying with new linear oracle
    function _tryLogPTLinearAggregator(address _aggregator) internal view {
        if (Utils.tryGetPT(_aggregator) == address(0)) return;

        console2.log(
            "\tPrimary aggregator is Pendle PT linear aggregator for",
            IERC20Metadata(Utils.tryGetPT(_aggregator)).symbol(),
            "with base discount equal to",
            PriceFormatter.formatPriceInE18(IPTLinearAggregatorLike(_aggregator).baseDiscountPerYear())
        );
    }

    function _printPrice(ISiloOracle _oracle, address _baseToken, QuoteNamedAmount memory _quoteNamedAmount)
        internal
        view
    {
        (bool success, uint256 price) = Utils.quote(_oracle, _baseToken, _quoteNamedAmount.amount);

        if (success) {
            if (_quoteNamedAmount.logExponentialNotation) {
                console2.log("\tPrice for %s = %s", _quoteNamedAmount.name, PriceFormatter.formatPriceInE18(price));
            } else {
                console2.log("\tPrice for %s = %s", _quoteNamedAmount.name, price);
            }

            if (_quoteNamedAmount.quoteForOneToken && (price < 0.0001e18 || price > 200_000e18)) {
                console2.log(
                    "\t", WARNING_SYMBOL, "Price looks odd, check normalization, we expect 18 decimals for price \n"
                );
            }
        } else {
            console2.log("\t", WARNING_SYMBOL, "Price reverts for", _quoteNamedAmount.name);
        }
    }

    function _getAmountsToQuote(uint8 _baseTokenDecimals)
        internal
        pure
        returns (QuoteNamedAmount[] memory amountsToQuote)
    {
        amountsToQuote = new QuoteNamedAmount[](10);
        uint256 oneToken = (10 ** uint256(_baseTokenDecimals));

        amountsToQuote[0] = QuoteNamedAmount({
            amount: 1,
            name: "1 wei (lowest amount)",
            logExponentialNotation: false,
            quoteForOneToken: false
        });

        amountsToQuote[1] =
            QuoteNamedAmount({amount: 10, name: "10 wei", logExponentialNotation: false, quoteForOneToken: false});

        amountsToQuote[2] = QuoteNamedAmount({
            amount: oneToken / 10,
            name: "0.1 token",
            logExponentialNotation: true,
            quoteForOneToken: false
        });

        amountsToQuote[3] = QuoteNamedAmount({
            amount: oneToken / 2,
            name: "0.5 token",
            logExponentialNotation: true,
            quoteForOneToken: false
        });

        amountsToQuote[4] = QuoteNamedAmount({
            amount: oneToken,
            name: string.concat("1 token in own decimals (10^", Strings.toString(_baseTokenDecimals), ")"),
            logExponentialNotation: false,
            quoteForOneToken: true
        });

        amountsToQuote[5] = QuoteNamedAmount({
            amount: oneToken,
            name: string.concat("1 token in own decimals (10^", Strings.toString(_baseTokenDecimals), ") exp format"),
            logExponentialNotation: true,
            quoteForOneToken: true
        });

        amountsToQuote[6] = QuoteNamedAmount({
            amount: 100 * oneToken,
            name: "100 tokens",
            logExponentialNotation: true,
            quoteForOneToken: false
        });

        amountsToQuote[7] = QuoteNamedAmount({
            amount: 10_000 * oneToken,
            name: "10,000 tokens",
            logExponentialNotation: true,
            quoteForOneToken: false
        });

        amountsToQuote[8] = QuoteNamedAmount({
            amount: 10 ** 36,
            name: "10**36 wei",
            logExponentialNotation: true,
            quoteForOneToken: false
        });

        amountsToQuote[9] = QuoteNamedAmount({
            amount: 10 ** 20 * oneToken,
            name: "10**20 tokens (More than USA GDP if the token worth at least 0.001 cent)",
            logExponentialNotation: true,
            quoteForOneToken: false
        });
    }
}
