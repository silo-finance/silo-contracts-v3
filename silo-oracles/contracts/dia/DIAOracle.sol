// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from  "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {Aggregator} from "../_common/Aggregator.sol";
import {DIAOracleConfig} from "./DIAOracleConfig.sol";
import {IDIAOracle} from "../interfaces/IDIAOracle.sol";
import {IDIAOracleV2} from "../external/dia/IDIAOracleV2.sol";

// solhint-disable ordering

contract DIAOracle is ISiloOracle, IDIAOracle, Initializable, Aggregator, IVersioned {
    DIAOracleConfig public oracleConfig;

    /// @dev we accessing prices for assets by keys eg. "Jones/USD"
    /// I tried to store it as bytes32 immutable, but translation to string uses over 5K gas,
    /// reading string is less gas, because it is not immutable it is not stored in config contracts (less gas)
    mapping (DIAOracleConfig => string) public primaryKey;

    /// @dev key for secondary price
    mapping (DIAOracleConfig => string) public secondaryKey;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice validation of config is checked in factory, therefore you should not deploy and initialize directly
    /// use factory always.
    function initialize(
        DIAOracleConfig _configAddress,
        string memory _key1,
        string memory _key2
    )
        external
        virtual
        initializer
    {
        oracleConfig = _configAddress;

        primaryKey[_configAddress] = _key1;
        secondaryKey[_configAddress] = _key2;

        emit DIAConfigDeployed(_configAddress);
    }

    /// @inheritdoc ISiloOracle
    // solhint-disable-next-line code-complexity
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        DIAOracleConfig cacheOracleConfig = oracleConfig;
        DIAConfig memory data = cacheOracleConfig.getConfig();

        if (_baseToken != data.baseToken) revert AssetNotSupported();
        if (_baseAmount > type(uint128).max) revert BaseAmountOverflow();

        (
            uint128 assetPrice,
            bool priceUpToDate
        ) = getPriceForKey(data.diaOracle, primaryKey[cacheOracleConfig], data.heartbeat);

        if (!priceUpToDate) revert OldPrice();

        if (!data.convertToQuote) {
            quoteAmount = OracleNormalization.normalizePrice(
                _baseAmount, assetPrice, data.normalizationDivider, data.normalizationMultiplier
            );

            if (quoteAmount == 0) revert ZeroQuote();
            return quoteAmount;
        }

        (
            uint128 secondaryPrice, bool secondaryPriceValid
        ) = getPriceForKey(data.diaOracle, secondaryKey[cacheOracleConfig], data.heartbeat);

        if (!secondaryPriceValid) revert OldSecondaryPrice();

        quoteAmount = OracleNormalization.normalizePrices(
            _baseAmount,
            assetPrice,
            secondaryPrice,
            data.normalizationDivider,
            data.normalizationMultiplier,
            data.invertSecondPrice
        );

        if (quoteAmount == 0) revert ZeroQuote();
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        IDIAOracle.DIAConfig memory setup = oracleConfig.getConfig();
        return address(setup.quoteToken);
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "DIAOracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        IDIAOracle.DIAConfig memory config = oracleConfig.getConfig();
        return config.baseToken;
    }

    /// @param _diaOracle IDIAOracleV2 oracle where price is stored
    /// @param _key string under this key asset price will be available in DIA oracle
    /// @return assetPriceInUsd uint128 asset price
    /// @return priceUpToDate bool TRUE if price is up to date (acceptable), FALSE otherwise
    function getPriceForKey(IDIAOracleV2 _diaOracle, string memory _key, uint256)
        public
        view
        virtual
        returns (uint128 assetPriceInUsd, bool priceUpToDate)
    {
        uint128 priceTimestamp;
        (assetPriceInUsd, priceTimestamp) = _diaOracle.getValue(_key);
        if (priceTimestamp == 0) revert InvalidKey();

        // We are not checking assetPriceInUsd != 0, because this is checked on setup, so it will be always some value.
        // We are not checking heartbeat so price is always up to date.
        priceUpToDate = true;
    }
}
