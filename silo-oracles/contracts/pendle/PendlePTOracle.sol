// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {IPyYtLpOracleLike} from "silo-oracles/contracts/pendle/interfaces/IPyYtLpOracleLike.sol";
import {IPendleMarketV3Like} from "silo-oracles/contracts/pendle/interfaces/IPendleMarketV3Like.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {IPendleSYTokenLike} from "silo-oracles/contracts/pendle/interfaces/IPendleSYTokenLike.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Aggregator} from "../_common/Aggregator.sol";

// solhint-disable ordering

/// @notice PendlePTOracle is an oracle, which multiplies the underlying PT token price by PtToSyRate from Pendle.
/// This oracle must be deployed using PendlePTOracleFactory contract. PendlePTOracle decimals are equal to underlying
/// oracle's decimals. TWAP duration is constant and equal to 30 minutes. UNDERLYING_ORACLE must return the price of
/// PT token's underlying asset. Quote token of PendlePTOracle is equal to UNDERLYING_ORACLE quote token.
contract PendlePTOracle is ISiloOracle, Aggregator, IVersioned {
    /// @dev PtToSyRate unit of measurement.
    uint256 public constant PENDLE_RATE_PRECISION = 10 ** 18;

    /// @dev time range for TWAP to get PtToSyRate, in seconds.
    uint32 public constant TWAP_DURATION = 30 minutes;

    /// @dev oracle to get the price of PT underlying asset.
    ISiloOracle public immutable UNDERLYING_ORACLE; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle PyYtLpOracle to get PtToSyRate for a market.
    IPyYtLpOracleLike public immutable PENDLE_ORACLE; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle PT token address. Quote function returns the price of this asset.
    address public immutable PT_TOKEN; // solhint-disable-line var-name-mixedcase

    /// @dev PT_TOKEN underlying asset
    address public immutable PT_UNDERLYING_TOKEN; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle market for PT_TOKEN. This address is used to get PtToSyRate.
    address public immutable MARKET; // solhint-disable-line var-name-mixedcase

    /// @dev This oracle's quote token is equal to UNDERLYING_ORACLE's quote token.
    address public immutable QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase

    error InvalidUnderlyingOracle();
    error PendleOracleNotReady();
    error PendlePtToSyRateIsZero();
    error AssetNotSupported();
    error ZeroPrice();

    /// @dev constructor has sanity check for _underlyingOracle to not return zero or revert and for _pendleOracle to
    /// return non-zero value for _market address and TWAP_DURATION. If underlying oracle reverts, constructor will
    /// revert with original revert reason.
    constructor(
        ISiloOracle _underlyingOracle,
        IPyYtLpOracleLike _pendleOracle,
        address _market
    ) {
        address ptToken = getPtToken(_market);
        address ptUnderlyingToken = getPtUnderlyingToken(_market);
        uint256 ptUnderlyingTokenDecimals = TokenHelper.assertAndGetDecimals(ptUnderlyingToken);

        (bool increaseCardinalityRequired,, bool oldestObservationSatisfied) =
            _pendleOracle.getOracleState(_market, TWAP_DURATION);

        require(oldestObservationSatisfied && !increaseCardinalityRequired, PendleOracleNotReady());
        require(_pendleOracle.getPtToSyRate(_market, TWAP_DURATION) != 0, PendlePtToSyRateIsZero());

        uint256 underlyingSampleToQuote = 10 ** ptUnderlyingTokenDecimals;
        require(_underlyingOracle.quote(underlyingSampleToQuote, ptUnderlyingToken) != 0, InvalidUnderlyingOracle());

        UNDERLYING_ORACLE = _underlyingOracle;
        PENDLE_ORACLE = _pendleOracle;
        PT_TOKEN = ptToken;
        PT_UNDERLYING_TOKEN = ptUnderlyingToken;
        MARKET = _market;

        QUOTE_TOKEN = _underlyingOracle.quoteToken();
    }

    /// @inheritdoc ISiloOracle
    function beforeQuote(address) external virtual {}

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        require(_baseToken == PT_TOKEN, AssetNotSupported());
        uint256 rate = PENDLE_ORACLE.getPtToSyRate(MARKET, TWAP_DURATION);

        // Price of PT token is defined as the price of underlying asset multiplied by PtToSyRate. PtToSyRate can be
        // more than 10**18 when decimals of PT token are less than decimals of underlying asset. In this case the
        // rate multiplier is applied to token amounts to improve the precision of calculations.
        if (rate <= PENDLE_RATE_PRECISION) {
            quoteAmount = UNDERLYING_ORACLE.quote(_baseAmount, PT_UNDERLYING_TOKEN);
            quoteAmount = Math.mulDiv(quoteAmount, rate, PENDLE_RATE_PRECISION);
        } else {
            uint256 underlyingAmount = Math.mulDiv(_baseAmount, rate, PENDLE_RATE_PRECISION);
            quoteAmount = UNDERLYING_ORACLE.quote(underlyingAmount, PT_UNDERLYING_TOKEN);
        }

        require(quoteAmount != 0, ZeroPrice());
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external virtual view returns (address) {
        return QUOTE_TOKEN;
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "PendlePTOracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return PT_TOKEN;
    }

    function getPtToken(address _market) public virtual view returns (address ptToken) {
        (, ptToken,) = IPendleMarketV3Like(_market).readTokens();
    }

    function getPtUnderlyingToken(address _market) public virtual view returns (address ptUnderlyingToken) {
        (address syToken,,) = IPendleMarketV3Like(_market).readTokens();
        ptUnderlyingToken = IPendleSYTokenLike(syToken).yieldToken();
    }
}
