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

/// @notice PendlePTToAssetOracle is an oracle, which multiplies the SY.assetInfo() asset price by PtToAssetRate.
/// This oracle must be deployed using PendlePTToAssetOracleFactory contract. TWAP duration is constant and equal
/// to 30 minutes. UNDERLYING_ORACLE must return the price of SY.assetInfo() asset. Quote token
/// of PendlePTToAssetOracle is equal to UNDERLYING_ORACLE quote token. PendlePTToAssetOracle decimals are equal
/// to underlying oracle's decimals.
/// This oracle must be used for Pendle PT tokens with rebasing underlying assets and other cases with SY-to-asset
/// rate not equal to 100%. These cases are described here
/// https://docs.pendle.finance/Developers/Contracts/StandardizedYield#non-standard-sys
contract PendlePTToAssetOracle is ISiloOracle, Aggregator, IVersioned {
    /// @dev PtToAssetRate unit of measurement.
    uint256 public constant PENDLE_RATE_PRECISION = 10 ** 18;

    /// @dev time range for TWAP to get PtToAssetRate, in seconds.
    uint32 public constant TWAP_DURATION = 30 minutes;

    /// @dev oracle to get the price of SY.assetInfo() asset.
    ISiloOracle public immutable UNDERLYING_ORACLE; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle PyYtLpOracle to get PtToAssetRate for a market.
    IPyYtLpOracleLike public immutable PENDLE_ORACLE; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle PT token address. Quote function returns the price of this asset.
    address public immutable PT_TOKEN; // solhint-disable-line var-name-mixedcase

    /// @dev SY.assetInfo() asset (SY underlying asset)
    address public immutable SY_UNDERLYING_TOKEN; // solhint-disable-line var-name-mixedcase

    /// @dev Pendle market for PT_TOKEN. This address is used to get PtToAssetRate.
    address public immutable MARKET; // solhint-disable-line var-name-mixedcase

    /// @dev This oracle's quote token is equal to UNDERLYING_ORACLE's quote token.
    address public immutable QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase

    error InvalidUnderlyingOracle();
    error PendleOracleNotReady();
    error PendlePtToAssetRateIsZero();
    error AssetNotSupported();
    error ZeroPrice();

    /// @dev constructor has sanity check for _underlyingOracle to not return zero or revert and for _pendleOracle to
    /// return non-zero value for _market address and TWAP_DURATION. If underlying oracle reverts, constructor will
    /// revert with original revert reason.
    /// @param _underlyingOracle oracle for SY underlying asset.
    /// @param _pendleOracle Pendle PyYtLpOracle.
    /// @param _market Pendle market address to deploy this oracle for.
    constructor(
        ISiloOracle _underlyingOracle,
        IPyYtLpOracleLike _pendleOracle,
        address _market
    ) {
        address ptToken = getPtToken(_market);
        address syUnderlyingToken = getSyUnderlyingToken(_market);
        uint256 syUnderlyingTokenDecimals = TokenHelper.assertAndGetDecimals(syUnderlyingToken);

        (bool increaseCardinalityRequired,, bool oldestObservationSatisfied) =
            _pendleOracle.getOracleState(_market, TWAP_DURATION);

        require(oldestObservationSatisfied && !increaseCardinalityRequired, PendleOracleNotReady());
        require(_pendleOracle.getPtToAssetRate(_market, TWAP_DURATION) != 0, PendlePtToAssetRateIsZero());

        uint256 underlyingSampleToQuote = 10 ** syUnderlyingTokenDecimals;
        require(_underlyingOracle.quote(underlyingSampleToQuote, syUnderlyingToken) != 0, InvalidUnderlyingOracle());

        UNDERLYING_ORACLE = _underlyingOracle;
        PENDLE_ORACLE = _pendleOracle;
        PT_TOKEN = ptToken;
        SY_UNDERLYING_TOKEN = syUnderlyingToken;
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
        uint256 rate = PENDLE_ORACLE.getPtToAssetRate(MARKET, TWAP_DURATION);

        // Price of PT token is defined as the price of underlying asset multiplied by getPtToAssetRate.
        // getPtToAssetRate can be more than 10**18 when decimals of PT token are less than decimals of underlying
        // asset. In this case the rate multiplier is applied to token amounts to improve the precision of calculation.
        if (rate <= PENDLE_RATE_PRECISION) {
            quoteAmount = UNDERLYING_ORACLE.quote(_baseAmount, SY_UNDERLYING_TOKEN);
            quoteAmount = Math.mulDiv(quoteAmount, rate, PENDLE_RATE_PRECISION);
        } else {
            uint256 underlyingAmount = Math.mulDiv(_baseAmount, rate, PENDLE_RATE_PRECISION);
            quoteAmount = UNDERLYING_ORACLE.quote(underlyingAmount, SY_UNDERLYING_TOKEN);
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
        version = "PendlePTToAssetOracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    /// @dev This is equal to PT token address.
    function baseToken() public view virtual override returns (address token) {
        return PT_TOKEN;
    }

    function getPtToken(address _market) public virtual view returns (address ptToken) {
        (, ptToken,) = IPendleMarketV3Like(_market).readTokens();
    }

    function getSyUnderlyingToken(address _market) public virtual view returns (address syUnderlyingToken) {
        (address syToken,,) = IPendleMarketV3Like(_market).readTokens();
        (, syUnderlyingToken,) = IPendleSYTokenLike(syToken).assetInfo();
    }
}
