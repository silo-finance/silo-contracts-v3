// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import {OracleLibrary} from  "uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Pool} from  "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {RevertBytes} from  "../lib/RevertBytes.sol";
import {IUniswapV3Oracle} from "../interfaces/IUniswapV3Oracle.sol";
import {UniswapV3OracleConfig} from "./UniswapV3OracleConfig.sol";

// solhint-disable ordering

contract UniswapV3Oracle is ISiloOracle, IUniswapV3Oracle, IVersioned {
    using RevertBytes for bytes;

    /// @dev Uniswap can revert with "Old" error when begin of TWAP period is older than oldest observation.
    /// This hash is for catch this error.
    /// Assuming we checked for BufferFull (so we do have all required observations), we can safely reduce period
    /// to oldest available time and we can fetch price.
    /// NOTICE: buffer check is disabled (we not doing that check on oracle creation), that means it is possible
    /// to deploy oracle configured for TWAP N, even when there is not enough observations to provide that price.
    /// it is recommended to execute `adjustOracleCardinality` asap, even before deployment if possible.
    /// Reason for disabling this check is to allow early deployments. However it should not be used
    /// until buffer will be filled up because TWAP price can be invalid
    bytes32 public constant OLD_ERROR_HASH = keccak256(abi.encodeWithSignature("Error(string)", "OLD"));

    /// @dev deployment with configuration setup, can not be immutable because it is initialized
    UniswapV3OracleConfig public oracleConfig;

    constructor() {
        // disable initializer
        oracleConfig = UniswapV3OracleConfig(address(this));
    }

    /// @param _configAddress UniswapV3OracleConfig address
    function initialize(UniswapV3OracleConfig _configAddress) external virtual {
        if (address(oracleConfig) != address(0)) revert("Initializable: contract is already initialized");

        oracleConfig = _configAddress;
        emit UniswapV3ConfigDeployed(_configAddress);
    }

    /// @notice Adjust UniV3 pool cardinality to Silo's requirements.
    /// Call `observationsStatus` to see, if you need to execute this method.
    /// This method prepares pool for setup for price provider. In order to run `setupAsset` for asset,
    /// pool must have buffer to provide TWAP price. By calling this adjustment (and waiting necessary amount of time)
    /// pool will be ready for setup. It will collect valid number of observations, so the pool can be used
    /// once price data is ready.
    /// @dev Increases observation cardinality for univ3 oracle pool if needed, see getPrice desc for details.
    /// We should call it on init and when we are changing the pool (univ3 can have multiple pools for the same tokens)
    function adjustOracleCardinality() external virtual {
        UniswapV3Config memory config = oracleConfig.getConfig();

        (,,,, uint16 cardinalityNext,,) = config.pool.slot0();
        if (cardinalityNext >= config.requiredCardinality) revert("NotNecessary");

        // initialize required amount of slots, it will cost!
        config.pool.increaseObservationCardinalityNext(config.requiredCardinality);
    }

    /// @inheritdoc ISiloOracle
    /// @notice please check `_calculatePeriodAndTicks` for buffer comments
    /// @dev UniV3 saves price only on: mint, burn and swap.
    /// Mint and burn will write observation only when "current tick is inside the passed range" of ticks.
    /// I think that means, that if we minting/burning outside ticks range  (so outside current price)
    /// it will not modify observation. So we left with swap.
    ///
    /// Swap will write observation under this condition:
    ///     // update tick and write an oracle entry if the tick change
    ///     if (state.tick != slot0Start.tick) {
    /// that means, it is possible that price will be up to date (in a range of same tick)
    /// but observation timestamp will be old.
    ///
    /// Every pool by default comes with just one slot for observation (cardinality == 1).
    /// We can increase number of slots so TWAP price will be "better".
    /// When we increase, we have to wait until new tx will write new observation.
    /// Based on all above, we can tell how old is observation, but this does not mean the price is wrong.
    /// UniV3 recommends to use `observe` and `OracleLibrary.consult` uses it.
    /// `observe` reverts if `secondsAgo` > oldest observation, means, if there is any price observation in selected
    /// time frame, it will revert. Otherwise it will return either exact TWAP price or by interpolation.
    ///
    /// Conclusion: we can choose how many observation pool will be storing, but we need to remember,
    /// not all of them might be used to provide our price. Final question is: how many observations we need?
    ///
    /// How UniV3 calculates TWAP
    /// we ask for TWAP on time range ago:now using `OracleLibrary.consult`, it is all about find the right tick
    /// - we call `IUniswapV3Pool(pool).observe(secondAgo)` that returns two accumulator values (for ago and now)
    /// - each observation is resolved by `observeSingle`
    ///   - for _now_ we just using latest observation, and if it does not match timestamp, we interpolate (!)
    ///     and this is how we got the _tickCumulative_, so in extreme situation, if last observation was made day ago,
    ///     UniV3 will interpolate to reflect _tickCumulative_ at current time
    ///   - for _ago_ we search for observation using `getSurroundingObservations` that give us
    ///     before and after observation, base on which we calculate "avg" and we have target _tickCumulative_
    ///     - getSurroundingObservations: it's job is to find 2 observations based on which we calculate tickCumulative
    ///       here is where all calculations can revert, if ago < oldest observation, otherwise it will be calculated
    ///       either by interpolation or we will have exact match
    /// - now with both _tickCumulative_s we calculating TWAP
    ///
    /// recommended observations are = 30 min / blockTime
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override
        returns (uint256 quoteAmount)
    {
        if (_baseAmount > type(uint128).max) revert("Overflow");

        UniswapV3Config memory config = oracleConfig.getConfig();

        // this will force to optimise gas by not doing call for quote
        if (_baseToken == config.quoteToken) revert("UseBaseAmount");

        int24 timeWeightedAverageTick = _consult(config.pool, config.periodForAvgPrice);

        // Safe: `_baseAmount` is bounded by `uint128` in the guard above.
        // forge-lint: disable-next-line(unsafe-typecast)
        quoteAmount = OracleLibrary.getQuoteAtTick(
            // forge-lint: disable-next-line(unsafe-typecast)
            timeWeightedAverageTick, uint128(_baseAmount), _baseToken, config.quoteToken
        );

        // zero is also returned on invalid base token
        if (quoteAmount == 0) revert("ZeroQuote");
    }

    function quoteToken() external view override virtual returns (address) {
        return oracleConfig.getConfig().quoteToken;
    }

    function oldestTimestamp() external view virtual returns (uint32 oldestTimestamps) {
        UniswapV3Config memory config = oracleConfig.getConfig();

        (,, uint16 observationIndex, uint16 currentObservationCardinality,,,) = config.pool.slot0();

        oldestTimestamps
            = resolveOldestObservationTimestamp(config.pool, observationIndex, currentObservationCardinality);
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "UniswapV3Oracle 4.0.0";
    }

    function baseToken() public view virtual returns (address token) {
        UniswapV3Config memory config = oracleConfig.getConfig();
        return config.baseToken;
    }

    /// @param _pool uniswap V3 pool address
    /// @param _currentObservationIndex the most-recently updated index of the observations array
    /// @param _currentObservationCardinality the current maximum number of observations that are being stored
    /// @return lastObservationTimestamp last observation timestamp
    function resolveOldestObservationTimestamp(
        IUniswapV3Pool _pool,
        uint16 _currentObservationIndex,
        uint16 _currentObservationCardinality
    )
        public
        view
        virtual
        returns (uint32 lastObservationTimestamp)
    {
        bool initialized;

        (
            lastObservationTimestamp,,,
            initialized
        ) = _pool.observations((_currentObservationIndex + 1) % _currentObservationCardinality);

        // if not initialized, we just check id#0 as this will be the oldest
        if (!initialized) {
            (lastObservationTimestamp,,,) = _pool.observations(0);
        }
    }

    /// @notice Fetches time-weighted average tick using Uniswap V3 oracle
    /// @dev this is based on `OracleLibrary.consult`, we adjusted it to handle `OLD` error, time window will adjust
    /// to available pool observations
    /// @param _pool Address of Uniswap V3 pool that we want to observe
    /// @param _periodForAvgPrice TWAP period in seconds.
    /// Number of seconds for which time-weighted average should be calculated, ie. 1800 means 30 min
    /// @return timeWeightedAverageTick time-weighted average tick from (block.timestamp - period) to block.timestamp
    function _consult(IUniswapV3Pool _pool, uint32 _periodForAvgPrice)
        internal
        view
        virtual
        returns (int24 timeWeightedAverageTick)
    {
        (uint32 period, int56[] memory tickCumulatives) = _calculatePeriodAndTicks(_pool, _periodForAvgPrice);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // Safe: Uniswap V3 pool ticks are int24 by protocol design.
        // forge-lint: disable-next-line(unsafe-typecast)
        timeWeightedAverageTick = int24(tickCumulativesDelta / period);

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % period != 0)) timeWeightedAverageTick--;
    }

    /// @param _pool Address of Uniswap V3 pool
    /// @param _periodForAvgPrice TWAP period in seconds.
    /// Number of seconds for which time-weighted average should be calculated, ie. 1800 means 30 min
    /// @return period Number of seconds in the past to start calculating time-weighted average
    /// @return tickCumulatives Cumulative tick values as of each secondsAgos from the current block timestamp
    function _calculatePeriodAndTicks(IUniswapV3Pool _pool, uint32 _periodForAvgPrice)
        internal
        view
        virtual
        returns (uint32 period, int56[] memory tickCumulatives)
    {
        period = _periodForAvgPrice;
        bool old;

        (tickCumulatives, old) = _observe(_pool, period);

        if (old) {
            (,, uint16 observationIndex, uint16 currentObservationCardinality,,,) = _pool.slot0();

            uint32 latestTimestamp =
                resolveOldestObservationTimestamp(_pool, observationIndex, currentObservationCardinality);

            // WARNING: please check desc for `OLD_ERROR_HASH`
            // adjusting period to handle the case, where we might have enough observations but query period is beyond
            period = uint32(block.timestamp - latestTimestamp);

            (tickCumulatives, old) = _observe(_pool, period);
            if (old) revert("STILL OLD");
        }
    }

    /// @param _pool UniV3 pool address
    /// @param _period Number of seconds in the past to start calculating time-weighted average
    function _observe(IUniswapV3Pool _pool, uint32 _period)
        internal
        view
        virtual
        returns (int56[] memory tickCumulatives, bool old)
    {
        uint32[] memory secondAgos = new uint32[](2);
        secondAgos[0] = _period;
        // secondAgos[1] = 0; // default is 0

        try _pool.observe(secondAgos)
            returns (int56[] memory ticks, uint160[] memory)
        {
            tickCumulatives = ticks;
            old = false;
        }
        catch (bytes memory reason) {
            if (keccak256(reason) != OLD_ERROR_HASH) reason.revertBytes("_observe");
            old = true;
        }
    }
}
