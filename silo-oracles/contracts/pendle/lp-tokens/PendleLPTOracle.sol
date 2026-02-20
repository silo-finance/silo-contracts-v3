// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {IPendleOracleHelper} from "silo-oracles/contracts/pendle/interfaces/IPendleOracleHelper.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {Aggregator} from "../../_common/Aggregator.sol";

// solhint-disable ordering

abstract contract PendleLPTOracle is ISiloOracle, Aggregator, IVersioned {
    /// @dev getLpToSyRate unit of measurement.
    uint256 public constant PENDLE_RATE_PRECISION = 10 ** 18;

    /// @dev time range for TWAP to get getLpToSyRate, in seconds.
    uint32 public constant TWAP_DURATION = 30 minutes;

    /// @dev Pendle oracle helper to get getLpToSyRate for a PENDLE_MARKET.
    /// It was deployed to have the same address for all networks.
    /// https://docs.pendle.finance/Developers/Oracles/HowToIntegratePtAndLpOracle
    IPendleOracleHelper public constant PENDLE_ORACLE =
        IPendleOracleHelper(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    /// @dev oracle to get the price of LP underlying asset.
    ISiloOracle public immutable UNDERLYING_ORACLE; // solhint-disable-line var-name-mixedcase

    /// @dev LP_TOKEN underlying asset.
    address public immutable UNDERLYING_TOKEN; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle market. This address is used to get getLpToSyRate.
    address public immutable PENDLE_MARKET; // solhint-disable-line var-name-mixedcase

    /// @dev This oracle's quote token is equal to UNDERLYING_ORACLE's quote token.
    address public immutable QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase

    error InvalidUnderlyingOracle();
    error IncreaseCardinalityRequired();
    error OldestObservationSatisfied();
    error PendleRateIsZero();
    error AssetNotSupported();
    error ZeroPrice();

    /// @dev constructor has sanity check for _underlyingOracle to not return zero or revert and for _pendleOracle to
    /// return non-zero value for _pendleMarket address and TWAP_DURATION. If underlying oracle reverts,
    /// constructor will revert with original revert reason.
    constructor(ISiloOracle _underlyingOracle, address _pendleMarket) {
        PENDLE_MARKET = _pendleMarket;

        address underlyingToken = _getUnderlyingToken();

        (bool increaseCardinalityRequired,, bool oldestObservationSatisfied) =
            PENDLE_ORACLE.getOracleState(_pendleMarket, TWAP_DURATION);

        require(!increaseCardinalityRequired, IncreaseCardinalityRequired());
        require(oldestObservationSatisfied, OldestObservationSatisfied());
        require(_getRateLpToUnderlying() != 0, PendleRateIsZero());

        uint256 underlyingSampleToQuote = 10 ** TokenHelper.assertAndGetDecimals(underlyingToken);
        require(_underlyingOracle.quote(underlyingSampleToQuote, underlyingToken) != 0, InvalidUnderlyingOracle());

        UNDERLYING_ORACLE = _underlyingOracle;
        UNDERLYING_TOKEN = underlyingToken;

        QUOTE_TOKEN = _underlyingOracle.quoteToken();
    }

    /// @inheritdoc ISiloOracle
    /// @dev Pendle LPs might be susceptible to read-only reentrancy IF the underlying yieldToken
    /// surrenders the control flow to an external caller at any point.
    /// Contact Pendle team before deploying this oracle.
    function beforeQuote(address) external virtual {}

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        require(_baseToken == _getBaseToken(), AssetNotSupported());

        quoteAmount = UNDERLYING_ORACLE.quote(_baseAmount, UNDERLYING_TOKEN);
        quoteAmount = quoteAmount * _getRateLpToUnderlying() / PENDLE_RATE_PRECISION;

        require(quoteAmount != 0, ZeroPrice());
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return QUOTE_TOKEN;
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "PendleLPTOracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return _getBaseToken();
    }

    function _getBaseToken() internal view virtual returns (address token) {
        token = PENDLE_MARKET;
    }

    function _getRateLpToUnderlying() internal view virtual returns (uint256);
    function _getUnderlyingToken() internal view virtual returns (address);
}
