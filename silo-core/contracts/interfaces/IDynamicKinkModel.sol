// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IDynamicKinkModelConfig} from "./IDynamicKinkModelConfig.sol";

/// @title IDynamicKinkModel
/// @notice Interface for the Dynamic Kink Interest Rate Model
/// @dev This interface defines an adaptive interest rate model that dynamically adjusts rates based on market
///      utilization.
///      The model uses a "kink" mechanism where interest rates change more aggressively as utilization increases.
///      Unlike static models, this implementation adapts over time to market conditions.
/// 
///      Key Features:
///      - Dynamic rate adjustment based on utilization thresholds
///      - Time-based rate evolution to prevent sudden spikes
///      - Configurable parameters for different market conditions
///      - Compound interest calculation for accurate accrual
/// 
///      The model operates with several utilization zones:
///      - Low utilization (0 to ulow): Minimal rates to encourage borrowing
///      - Optimal range (u1 to u2): Stable rates for normal operations  
///      - High utilization (u2 to ucrit): Increasing rates to manage risk
///      - Critical utilization (ucrit to 1e18): Maximum rates
interface IDynamicKinkModel {
    /// @notice User-friendly configuration structure for setting up the Dynamic Kink Model
    /// @dev This structure provides intuitive parameters that are converted to internal model parameters.
    ///      All utilization values are in 18 decimals (e.g., 0.5e18 = 50% utilization).
    ///      All time values are in seconds.
    /// 
    /// @param ulow Utilization threshold below which rates are minimal
    /// @param ucrit Critical utilization threshold where rates become very high
    /// @param u1 lower bound of optimal utilization range (the model is static when utilization is in this interval).
    /// @param u2 upper bound of optimal utilization range (the model is static when utilization is in this interval).
    /// @param rmin Minimal per-second interest rate (minimal APR), active below ulow.
    /// @param rcritMin Minimal APR that the model can output at the critical utilization ucrit
    /// @param rcritMax Maximal APR that the model can output at the critical utilization ucrit
    /// @param r100 Maximum possible per-second rate at 100% utilization
    /// @param t1 Time in seconds for rate to decrease from max to min at u1 utilization
    /// @param t2 Time in seconds for rate to increase from min to max at u2 utilization
    /// @param tlow Time in seconds to reset rates when utilization drops to ulow
    /// @param tcrit Time in seconds for rate to increase from min to max at critical utilization
    /// @param tMin minimal time it takes to grow from the minimal to the maximal APR at any utilization
    struct UserFriendlyConfig {
        uint64 ulow;
        uint64 ucrit;
        uint64 u1;
        uint64 u2;
        uint72 rmin;
        uint72 rcritMin;
        uint72 rcritMax;
        uint72 r100;
        uint32 t1;
        uint32 t2;
        uint32 tlow;
        uint32 tcrit;
        uint32 tMin;
    }

    /// @dev same as UserFriendlyConfig but with int256 values to help with calculations
    struct UserFriendlyConfigInt {
        int256 ulow;
        int256 ucrit;
        int256 u1;
        int256 u2;
        int256 rmin;
        int256 rcritMin;
        int256 rcritMax;
        int256 r100;
        int256 t1;
        int256 t2;
        int256 tlow;
        int256 tcrit;
        int256 tMin;
    }

    /// @notice Internal configuration structure used by the model for calculations
    /// @dev These values are used in the mathematical calculations of the interest rate model.
    ///     Utilization values are in 18 decimals 1e18 = 100%.
    /// @param ulow ulow ∈ [0, 1e18) Low utilization threshold
    /// @param u1 u1 ∈ [0, 1e18) Lower bound of optimal utilization range
    /// @param u2 u2 ∈ [u1, 1e18) Upper bound of optimal utilization range
    /// @param ucrit ucrit ∈ [ulow, 1e18) Critical utilization threshold
    /// @param rmin rmin >= 0 Minimal per-second interest rate
    /// @param kmin kmin >= 0 Minimal slope k of central segment (curve) of the kink
    /// @param kmax kmax >= kmin Maximal slope k of central segment (curve) of the kink
    /// @param alpha alpha >= 0 Factor controlling the slope for the critical segment of the kink
    /// @param cminus cminus >= 0 Coefficient of decrease of the slope k
    /// @param cplus cplus >= 0 Coefficient for increasing the slope k
    /// @param c1 c1 >= 0 Minimal rate of decrease of the slope k
    /// @param c2 c2 >= 0 Minimal growth rate of the slope k
    /// @param dmax dmax >= 0 Maximum growth rate of the slope k
    struct Config {
        int256 ulow;
        int256 u1;
        int256 u2;
        int256 ucrit;
        int256 rmin;
        int96 kmin;
        int96 kmax;
        int256 alpha;
        int256 cminus;
        int256 cplus;
        int256 c1;
        int256 c2;
        int256 dmax;
    }

    struct ImmutableArgs {
        uint32 timelock;
        int96 rcompCap;
    }

    struct ImmutableConfig {
        uint32 timelock;
        int96 rcompCapPerSecond;
    }

    /// @notice Internal variables used during compound interest calculations
    /// @dev This structure contains temporary variables used in the mathematical calculations.
    ///      Integrators typically don't need to interact with these values directly.
    /// 
    /// @param T Time elapsed since the last interest rate update (in seconds)
    /// @param k1 Internal variable for slope calculations
    /// @param f Factor used in kink slope calculations
    /// @param roc Rate of change variable for slope calculations
    /// @param x Internal calculation variable
    /// @param interest Absolute value of compounded interest
    // forge-lint: disable-next-item(pascal-case-struct)
    struct LocalVarsRCOMP {
        int256 T;
        int256 k1;
        int256 f;
        int256 roc;
        int256 x;
        int256 interest;
    }

    struct CompoundInterestRateArgs {
        address silo;
        uint256 collateralAssets;
        uint256 debtAssets;
        uint256 interestRateTimestamp;
        uint256 blockTimestamp;
        bool usePending;
    }

    /// @notice Current state of the Dynamic Kink Model
    /// @dev This structure tracks the current state of the model, including the dynamic slope value
    ///      that changes over time based on utilization patterns.
    /// 
    /// @param k Current slope value of the kink curve (changes dynamically over time)
    /// @param silo Address of the Silo contract this model is associated with
    struct ModelState {
        int96 k;
        address silo;
    }

    struct History {
        int96 k;
        IDynamicKinkModelConfig irmConfig;
    }

    /// @notice Emitted when the model is initialized with a new configuration
    /// @param owner Address that will own this model instance
    /// @param silo Address of the Silo contract this model is associated with
    event Initialized(address indexed owner, address indexed silo);

    /// @notice Emitted when a new configuration is set for the model
    /// @param config The new configuration contract address
    /// @param activeAt Timestamp at which the configuration becomes active
    event NewConfig(IDynamicKinkModelConfig indexed config, uint256 activeAt);

    /// @notice Emitted when a pending configuration update is canceled
    /// @param config The canceled configuration contract address
    event PendingUpdateConfigCanceled(IDynamicKinkModelConfig indexed config);

    error AddressZero();
    error AlphaDividerZero();
    error AlreadyInitialized();
    error EmptySilo();
    error InvalidAlpha();
    error InvalidC1();
    error InvalidC2();
    error InvalidCminus();
    error InvalidCplus();
    error InvalidDefaultConfig();
    error InvalidDmax();
    error InvalidKmax();
    error InvalidKmin();
    error InvalidKRange();
    error InvalidRcompCap();
    error InvalidRcritMax();
    error InvalidRcritMin();
    error InvalidRmin();
    error InvalidSilo();
    error InvalidT1();
    error InvalidT2();
    error InvalidTimelock();
    error InvalidTimestamp();
    error InvalidTMin();
    error InvalidTLow();
    error InvalidTCrit();
    error InvalidU1();
    error InvalidU2();
    error InvalidUcrit();
    error InvalidUlow();
    error NegativeRcomp();
    error NegativeRcur();
    error NoPendingUpdateToCancel();
    error NoPendingConfig();
    error OnlySilo();
    error PendingUpdate();
    error XOverflow();

    /// @notice Initialize the Dynamic Kink Model with configuration and ownership
    /// @dev This function sets up the model for a specific Silo contract. Can only be called once.
    /// @param _config The configuration parameters for the interest rate model
    /// @param _immutableArgs The immutable configuration parameters for the interest rate model
    /// @param _initialOwner Address that will own and control this model instance
    /// @param _silo Address of the Silo contract this model will serve
    function initialize(
        IDynamicKinkModel.Config calldata _config, 
        IDynamicKinkModel.ImmutableArgs calldata _immutableArgs, 
        address _initialOwner, 
        address _silo
    ) 
        external;

    /// @notice Update the model configuration
    /// @dev This function allows the model owner to update the configuration of the model.
    ///      By setting the same config, we can reset k to kmin.
    /// @param _config The new configuration parameters for the interest rate model
    function updateConfig(IDynamicKinkModel.Config calldata _config) external;

    /// @notice Cancel the pending configuration update
    /// @dev This function allows the model owner to cancel the pending configuration update.
    ///      It will revert if there is no pending update.
    function cancelPendingUpdateConfig() external;

    /// @notice Calculate compound interest rate and update the model's internal state
    /// @dev This function is the primary method used by Silo contracts to calculate
    ///      and accrue interest. Unlike getCompoundInterestRate(), this function
    ///      modifies the model's internal state by updating the dynamic slope value (k).
    /// 
    ///      This function should only be called by the associated Silo contract,
    ///      as it performs state updates that affect future interest calculations.
    ///      It includes comprehensive overflow protection and gracefully handles
    ///      calculation errors by returning 0 and resetting the slope to minimum.
    /// 
    ///      The function calculates interest based on:
    ///      - Current collateral and debt amounts
    ///      - Time elapsed since last interest rate update
    ///      - Dynamic slope adjustments based on utilization patterns
    /// 
    /// @param _collateralAssets Total collateral assets in the Silo (in asset units)
    /// @param _debtAssets Total debt assets in the Silo (in asset units)
    /// @param _interestRateTimestamp Timestamp of the last interest rate update
    /// @return rcomp Total compound interest multiplier (in 18 decimals, represents total accrued interest)
    /// @custom:throws OnlySilo() if called by any address other than the associated Silo contract
    function getCompoundInterestRateAndUpdate(
        uint256 _collateralAssets,
        uint256 _debtAssets,
        uint256 _interestRateTimestamp
    )
        external
        returns (uint256 rcomp);
    
    function configsHistory(IDynamicKinkModelConfig _irmConfig) 
        external 
        view 
        returns (int96 k, IDynamicKinkModelConfig irmConfig);

    /// @notice Get the current (active) configuration contract for this model
    /// @return config The IDynamicKinkModelConfig contract containing the model parameters
    function irmConfig() external view returns (IDynamicKinkModelConfig config);

    /// @notice Get the current (active) model state
    function modelState() external view returns (ModelState memory state);
    
    /// @notice Get both the current model state and configuration
    /// @param _usePending Whether to use the pending configuration to pull config from
    /// @return state Current state of the model (including dynamic slope value)
    /// @return config configuration parameters, either active or pending, depending on _usePending
    /// @return immutableConfig Immutable configuration parameters
    function getModelStateAndConfig(bool _usePending) 
        external 
        view 
        returns (ModelState memory state, Config memory config, ImmutableConfig memory immutableConfig);

    /// @notice Maximum compound interest rate per second (prevents extreme rates)
    /// @return cap Maximum per-second compound interest rate in 18 decimals
    function RCOMP_CAP_PER_SECOND() external view returns (int256 cap); // solhint-disable-line func-name-mixedcase
    
    /// @notice Maximum current interest rate (prevents extreme APRs)
    /// @return cap Maximum annual interest rate in 18 decimals (e.g., 25e18 = 2500% APR)
    function RCUR_CAP() external view returns (int256 cap); // solhint-disable-line func-name-mixedcase

    /// @notice Number of seconds in one year (used for rate calculations)
    /// @return secondsInYear Seconds in one year (365 days)
    function ONE_YEAR() external view returns (int256 secondsInYear); // solhint-disable-line func-name-mixedcase
    
    /// @notice Maximum input value for exponential calculations (prevents overflow)
    /// @return max Maximum safe input value for exp() function
    function X_MAX() external view returns (int256 max); // solhint-disable-line func-name-mixedcase
    
    /// @notice Universal limit for various model parameters
    /// @return limit Maximum allowed value for certain configuration parameters
    function UNIVERSAL_LIMIT() external view returns (int256 limit); // solhint-disable-line func-name-mixedcase

    /// @notice Maximum time lock for configuration changes
    /// @return maxTimeLock Maximum time lock for configuration changes
    function MAX_TIMELOCK() external view returns (uint32 maxTimeLock); // solhint-disable-line func-name-mixedcase

    /// @return timestamp Timestamp at which the pending configuration becomes active
    function activateConfigAt() external view returns (uint256 timestamp);

    /// @return pendingIrmConfig Pending irm config for configuration changes, 0 if no pending
    function pendingIrmConfig() external view returns (address pendingIrmConfig);

    /// @notice Validate that configuration parameters are within acceptable limits
    /// @dev This function checks if all configuration parameters are within the safe operating ranges
    ///      defined by the model whitepaper. Some limits are narrower than the original whitepaper
    ///      due to additional research and safety considerations.
    /// 
    ///      For detailed limits, see:
    ///      https://silofinance.atlassian.net/wiki/spaces/SF/pages/347963393/DynamicKink+model+config+limits+V1
    /// 
    /// @param _config The configuration to validate (does not include model state)
    /// @custom:throws Reverts if any parameter is outside acceptable limits
    function verifyConfig(IDynamicKinkModel.Config calldata _config) external view;

    /// @notice Calculate compound interest rate for a specific Silo at a given timestamp
    /// @dev This function calculates the total compound interest that has accrued over time
    ///      for a specific Silo contract.
    /// 
    ///      The function fetches current utilization data from the Silo contract and
    ///      calculates interest based on the time elapsed since the last rate update.
    ///      It handles overflow protection and returns 0 if calculations would overflow.
    /// 
    /// @param _silo Address of the Silo contract to calculate interest for
    /// @param _blockTimestamp Timestamp to calculate interest up to (usually block.timestamp)
    /// @return rcomp Total compound interest multiplier (in 18 decimals, represents total accrued interest)
    /// @custom:throws InvalidSilo() if the provided Silo address doesn't match this model's associated Silo
    function getCompoundInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        returns (uint256 rcomp);

    /// @notice Same as getCompoundInterestRate but uses pending configuration, throws if no pending
    function getPendingCompoundInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        returns (uint256 rcomp);

    /// @notice get current annual interest rate
    /// @param _silo address of Silo for which interest rate should be calculated
    /// @param _blockTimestamp timestamp to calculate interest up to (usually block.timestamp)
    /// @return rcur current annual interest rate (1e18 == 100%)
    function getCurrentInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        returns (uint256 rcur);

    /// @notice Same as getCurrentInterestRate but uses pending configuration, throws if no pending
    function getPendingCurrentInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        returns (uint256 rcur);

    /// @notice Calculate the compound interest rate for a given time period
    /// @dev This function calculates how much interest has accrued over a time period,
    ///      taking into account the dynamic nature of the kink model. The rate changes
    ///      over time based on utilization patterns and the model's adaptive behavior.
    /// 
    ///      This is the core function used by Silo contracts to determine how much
    ///      interest borrowers owe and how much lenders should receive.
    /// 
    /// @param _cfg Model configuration parameters
    /// @param _state Current model state (including dynamic slope value)
    /// @param _rcompCapPerSecond Maximum compound interest rate per second
    /// @param _t0 Timestamp of the last interest rate update
    /// @param _t1 Current timestamp for the calculation
    /// @param _u Utilization ratio at time _t0 (0 to 1e18, where 1e18 = 100% utilized)
    /// @param _tba Total borrowed amount at time _t1
    /// @return rcomp Total compound interest accrued over the time period (in 18 decimals, represents multiplier)
    /// @return k Updated model state (new slope value) at time _t1
    function compoundInterestRate(
        Config memory _cfg,
        ModelState memory _state,
        int256 _rcompCapPerSecond,
        int256 _t0,
        int256 _t1,
        int256 _u,
        int256 _tba
    )
        external
        pure
        returns (int256 rcomp, int256 k);

    /// @notice Calculate the current instantaneous interest rate
    /// @dev This function returns the current interest rate that would apply if a new
    ///      transaction were to occur right now. Unlike compoundInterestRate, this
    ///      doesn't calculate accrued interest over time, but rather the rate at
    ///      the current moment.
    /// 
    ///      This is useful for:
    ///      - Displaying current rates to users
    ///      - Calculating what rate would apply to new borrows
    ///      - Monitoring rate changes in real-time
    /// 
    /// @param _cfg Model configuration parameters
    /// @param _state Current model state (including dynamic slope value)
    /// @param _t0 Timestamp of the last interest rate update
    /// @param _t1 Current timestamp for the calculation
    /// @param _u Current utilization ratio (0 to 1e18, where 1e18 = 100% utilized)
    /// @param _tba Current total borrowed amount
    /// @return rcur Current instantaneous interest rate (in 18 decimals, annual rate)
    function currentInterestRate(
        Config memory _cfg,
        ModelState memory _state,
        int256 _t0,
        int256 _t1,
        int256 _u,
        int256 _tba
    )
        external
        pure
        returns (int256 rcur);
}
