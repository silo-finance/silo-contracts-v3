// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";
import {SignedMath} from "openzeppelin5/utils/math/SignedMath.sol";
import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";

import {Ownable1and2Steps} from "common/access/Ownable1and2Steps.sol";

import {PRBMathSD59x18} from "../../lib/PRBMathSD59x18.sol";
import {ISilo} from "../../interfaces/ISilo.sol";
import {IDynamicKinkModel} from "../../interfaces/IDynamicKinkModel.sol";
import {IDynamicKinkModelConfig} from "../../interfaces/IDynamicKinkModelConfig.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";

import {DynamicKinkModelConfig} from "./DynamicKinkModelConfig.sol";
import {KinkMath} from "../../lib/KinkMath.sol";
import {SiloMathLib} from "../../lib/SiloMathLib.sol";

/// @title DynamicKinkModel
/// @notice Refer to Silo DynamicKinkModel paper for more details:
/// silo-core/docs/Kink_Interest_Rate_Model_V2_2025_09_23.pdf
/// @dev it follows `IInterestRateModel` interface except `initialize` method
/// @custom:security-contact security@silo.finance
contract DynamicKinkModel is IDynamicKinkModel, IVersioned, Ownable1and2Steps, Initializable {
    using KinkMath for int256;
    using KinkMath for int96;
    using KinkMath for uint256;

    string public constant VERSION = "DynamicKinkModel 4.1.3";

    /// @dev DP in 18 decimal points used for integer calculations
    int256 internal constant _DP = int256(1e18);

    /// @dev universal limit for several DynamicKinkModel config parameters. Follow the model whitepaper for more
    ///     information. Units of measure vary per variable type. Any config within these limits is considered
    ///     valid.
    int256 public constant UNIVERSAL_LIMIT = 1e9 * _DP;

    /// @dev maximum value of current interest rate the model will return. This is 1,000% APR in 18-decimals.
    int256 public constant RCUR_CAP = 10 * _DP;

    /// @dev seconds per year used in interest calculations.
    int256 public constant ONE_YEAR = 365 days;

    /// @dev maximum value of compound interest per second the model will return. This is per-second rate.
    int256 public constant RCOMP_CAP_PER_SECOND = RCUR_CAP / ONE_YEAR;

    /// @dev maximum exp() input to prevent an overflow.
    int256 public constant X_MAX = 11 * _DP;

    uint32 public constant MAX_TIMELOCK = 7 days;

    /// @dev this is used for storing the current or pending model state
    ModelState internal _modelState;

    /// @inheritdoc IDynamicKinkModel
    uint256 public activateConfigAt;

    /// @dev Map of all configs for the model, used for restoring to last state
    mapping(IDynamicKinkModelConfig current => History prev) public configsHistory;

    IDynamicKinkModelConfig internal _irmConfig;

    constructor() Ownable1and2Steps(address(0xdead)) {
        // lock the implementation
        _transferOwnership(address(0));
        _disableInitializers();
    }

    function initialize(
        IDynamicKinkModel.Config calldata _config,
        IDynamicKinkModel.ImmutableArgs calldata _immutableArgs,
        address _initialOwner,
        address _silo
    )
        external
        virtual
        initializer
    {
        require(_silo != address(0), EmptySilo());
        require(_immutableArgs.timelock <= MAX_TIMELOCK, InvalidTimelock());
        require(_immutableArgs.rcompCap > 0, InvalidRcompCap());
        require(_immutableArgs.rcompCap <= RCUR_CAP, InvalidRcompCap());

        IDynamicKinkModel.ImmutableConfig memory immutableConfig = IDynamicKinkModel.ImmutableConfig({
            timelock: _immutableArgs.timelock,
            rcompCapPerSecond: int96(_immutableArgs.rcompCap / ONE_YEAR) // forge-lint: disable-line(unsafe-typecast)
        });

        _modelState.silo = _silo;

        _updateConfiguration({_config: _config, _immutableConfig: immutableConfig, _init: true});

        _transferOwnership(_initialOwner);

        emit Initialized(_initialOwner, _silo);
    }

    /// @inheritdoc IDynamicKinkModel
    function updateConfig(IDynamicKinkModel.Config calldata _config) external virtual onlyOwner {
        _updateConfiguration(_config);
    }

    /// @inheritdoc IDynamicKinkModel
    function cancelPendingUpdateConfig() external virtual onlyOwner {
        require(pendingConfigExists(), NoPendingUpdateToCancel());

        IDynamicKinkModelConfig pendingConfig = _irmConfig;
        History memory currentState = configsHistory[pendingConfig];

        _irmConfig = currentState.irmConfig;
        _modelState.k = currentState.k;

        configsHistory[pendingConfig] = History({k: 0, irmConfig: IDynamicKinkModelConfig(address(0))});

        activateConfigAt = 0;

        emit PendingUpdateConfigCanceled(pendingConfig);
    }

    /// @inheritdoc IDynamicKinkModel
    function getCompoundInterestRateAndUpdate(
        uint256 _collateralAssets,
        uint256 _debtAssets,
        uint256 _interestRateTimestamp
    )
        external
        virtual
        returns (uint256 rcomp) 
    {
        int96 newK;
        uint256 result; 

        (result, newK) = _getCompoundInterestRate(CompoundInterestRateArgs({
            silo: msg.sender,
            collateralAssets: _collateralAssets,
            debtAssets: _debtAssets,
            interestRateTimestamp: _interestRateTimestamp,
            blockTimestamp: block.timestamp,
            usePending: false
        }));

        rcomp = result;

        if (pendingConfigExists()) {
            configsHistory[_irmConfig].k = newK;
        } else {
            _modelState.k = newK;
        }
    }

    /// @inheritdoc IDynamicKinkModel
    function getCompoundInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        virtual
        returns (uint256 rcomp)
    {
        (rcomp,) = _getCompoundInterestRate({_silo: _silo, _blockTimestamp: _blockTimestamp, _usePending: false});
    }

    function getPendingCompoundInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        virtual
        returns (uint256 rcomp)
    {
        (rcomp,) = _getCompoundInterestRate({_silo: _silo, _blockTimestamp: _blockTimestamp, _usePending: true});
    }

    /// @notice it reverts for invalid silo
    function getCurrentInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        virtual
        returns (uint256 rcur)
    {
        rcur = _getCurrentInterestRate({_silo: _silo, _blockTimestamp: _blockTimestamp, _usePending: false});
    }

    function getPendingCurrentInterestRate(address _silo, uint256 _blockTimestamp)
        external
        view
        virtual
        returns (uint256 rcur)
    {
        rcur = _getCurrentInterestRate({_silo: _silo, _blockTimestamp: _blockTimestamp, _usePending: true});
    }

    /// @inheritdoc IDynamicKinkModel
    function irmConfig() public view returns (IDynamicKinkModelConfig config) {
        config = pendingConfigExists() ? configsHistory[_irmConfig].irmConfig : _irmConfig;
    }

    /// @inheritdoc IDynamicKinkModel
    function modelState() public view returns (ModelState memory state) {
        if (!pendingConfigExists()) return _modelState;

        // in case of pending config, we need to read k from history
        state.silo = _modelState.silo;
        state.k = configsHistory[_irmConfig].k;
    }

    /// @inheritdoc IDynamicKinkModel
    function pendingIrmConfig() public view returns (address config) {
        config = pendingConfigExists() ? address(_irmConfig) : address(0);
    }

    /// @inheritdoc IDynamicKinkModel
    function getModelStateAndConfig(bool _usePending)
        public
        view
        virtual
        returns (ModelState memory state, Config memory config, ImmutableConfig memory immutableConfig)
    {
        IDynamicKinkModelConfig irmConfigToUse;

        if (_usePending) {
            irmConfigToUse = IDynamicKinkModelConfig(pendingIrmConfig());
            require(address(irmConfigToUse) != address(0), NoPendingConfig());

            state = _modelState;
        } else {
            irmConfigToUse = irmConfig();
            state = modelState();
        }

        (config, immutableConfig) = irmConfigToUse.getConfig();
    }

    /// @inheritdoc IDynamicKinkModel
    function verifyConfig(IDynamicKinkModel.Config memory _config) public view virtual {
        require(_config.ulow.inClosedInterval(0, _DP), InvalidUlow());
        require(_config.u1.inClosedInterval(0, _DP), InvalidU1());
        require(_config.u2.inClosedInterval(_config.u1, _DP), InvalidU2());

        require(_config.ucrit.inClosedInterval(_config.ulow, _DP), InvalidUcrit());

        require(_config.rmin.inClosedInterval(0, _DP), InvalidRmin());

        require(_config.kmin.inClosedInterval(0, UNIVERSAL_LIMIT), InvalidKmin());
        require(_config.kmax.inClosedInterval(_config.kmin, UNIVERSAL_LIMIT), InvalidKmax());

        // we store k as int96, so we double check if it is in the range of int96
        require(_config.kmin.inClosedInterval(0, type(int96).max), InvalidKmin());
        require(_config.kmax.inClosedInterval(_config.kmin, type(int96).max), InvalidKmax());

        require(_config.alpha.inClosedInterval(0, UNIVERSAL_LIMIT), InvalidAlpha());

        require(_config.cminus.inClosedInterval(0, UNIVERSAL_LIMIT), InvalidCminus());
        require(_config.cplus.inClosedInterval(0, UNIVERSAL_LIMIT), InvalidCplus());

        require(_config.c1.inClosedInterval(0, UNIVERSAL_LIMIT), InvalidC1());
        require(_config.c2.inClosedInterval(0, UNIVERSAL_LIMIT), InvalidC2());

        require(_config.dmax.inClosedInterval(_config.c2, UNIVERSAL_LIMIT), InvalidDmax());
    }

    function pendingConfigExists() public view returns (bool) {
        return activateConfigAt > block.timestamp;
    }

    /// @inheritdoc IDynamicKinkModel
    function currentInterestRate( // solhint-disable-line function-max-lines, code-complexity
        Config memory _cfg,
        ModelState memory _state, 
        int256 _t0, 
        int256 _t1,
        int256 _u,
        int256 _tba
    )
        public
        pure
        virtual
        returns (int256 rcur)
    {
        if (_tba == 0) return 0; // no debt, no interest

        int256 T = _t1 - _t0;

        // k is stored capped, so we can use it as is
        int256 k = _state.k;

        if (_u < _cfg.u1) {
            k = SignedMath.max(k - (_cfg.c1 + _cfg.cminus * (_cfg.u1 - _u) / _DP) * T, _cfg.kmin);
        } else if (_u > _cfg.u2) {
            k = SignedMath.min(
                k + SignedMath.min(_cfg.c2 + _cfg.cplus * (_u - _cfg.u2) / _DP, _cfg.dmax) * T, _cfg.kmax
            );
        }

        int256 excessU; // additional interest rate
        if (_u >= _cfg.ulow) {
            excessU = _u - _cfg.ulow;

            if (_u >= _cfg.ucrit) {
                excessU = excessU + _cfg.alpha * (_u - _cfg.ucrit) / _DP;
            }

            rcur = excessU * k * ONE_YEAR / _DP + _cfg.rmin * ONE_YEAR;
        } else {
            rcur = _cfg.rmin * ONE_YEAR;
        }

        require(rcur >= 0, NegativeRcur());
        rcur = SignedMath.min(rcur, RCUR_CAP);
    }

    /// @inheritdoc IDynamicKinkModel
    function compoundInterestRate( // solhint-disable-line code-complexity, function-max-lines
        Config memory _cfg,
        ModelState memory _state,
        int256 _rcompCapPerSecond,
        int256 _t0,
        int256 _t1,
        int256 _u,
        int256 _tba
    )
        public
        pure
        virtual
        returns (int256 rcomp, int256 k)
    {
        LocalVarsRCOMP memory _l;

        require(_t0 <= _t1, InvalidTimestamp());

        _l.T = _t1 - _t0;
        // if there is no time change, then k should not change
        if (_l.T == 0) return (0, _state.k);

        // rate of change of k
        if (_u < _cfg.u1) {
            _l.roc = -_cfg.c1 - _cfg.cminus * (_cfg.u1 - _u) / _DP;
        } else if (_u > _cfg.u2) {
            _l.roc = SignedMath.min(_cfg.c2 + _cfg.cplus * (_u - _cfg.u2) / _DP, _cfg.dmax);
        }

        k = _state.k;

        // slope of the kink at t1 ignoring lower and upper bounds
        _l.k1 = k + _l.roc * _l.T;

        // calculate the resulting slope state
        if (_l.k1 > _cfg.kmax) {
            _l.x = _cfg.kmax * _l.T - (_cfg.kmax - k) ** 2 / (2 * _l.roc);
            k = _cfg.kmax;
        } else if (_l.k1 < _cfg.kmin) {
            _l.x = _cfg.kmin * _l.T - (k - _cfg.kmin) ** 2 / (2 * _l.roc);
            k = _cfg.kmin;
        } else {
            _l.x = (k + _l.k1) * _l.T / 2;
            k = _l.k1;
        }

        if (_u >= _cfg.ulow) {
            _l.f = _u - _cfg.ulow;

            if (_u >= _cfg.ucrit) {
                _l.f = _l.f + _cfg.alpha * (_u - _cfg.ucrit) / _DP;
            }
        }

        _l.x = _cfg.rmin * _l.T + _l.f * _l.x / _DP;

        // Overflow Checks

        // limit x, so the exp() function will not overflow, we have unchecked math there
        require(_l.x <= X_MAX, XOverflow());

        rcomp = PRBMathSD59x18.exp(_l.x) - _DP;
        require(rcomp >= 0, NegativeRcomp());

        // limit rcomp
        if (rcomp > _rcompCapPerSecond * _l.T) {
            rcomp = _rcompCapPerSecond * _l.T;
            // k should be set to min only on overflow or cap
            k = _cfg.kmin;
        }

        // no debt, no interest, overriding min APR
        if (_tba == 0) rcomp = 0;
    }

    function _updateConfiguration(IDynamicKinkModel.Config memory _config) internal virtual {
        // even if _irmConfig is pending timelock, immutable config can be pulled from it
        (, IDynamicKinkModel.ImmutableConfig memory immutableConfig) = _irmConfig.getConfig();
        _updateConfiguration({_config: _config, _immutableConfig: immutableConfig, _init: false});
    }

    function _updateConfiguration(
        IDynamicKinkModel.Config memory _config,
        IDynamicKinkModel.ImmutableConfig memory _immutableConfig,
        bool _init
    ) internal virtual {
        require(!pendingConfigExists(), PendingUpdate());

        activateConfigAt = _init ? block.timestamp : block.timestamp + _immutableConfig.timelock;

        verifyConfig(_config);

        IDynamicKinkModelConfig newCfg = IDynamicKinkModelConfig(new DynamicKinkModelConfig(_config, _immutableConfig));

        configsHistory[newCfg] = History({k: _modelState.k, irmConfig: _irmConfig});
        _modelState.k = _config.kmin;
        _irmConfig = newCfg;

        emit NewConfig(newCfg, activateConfigAt);
    }

    function _getCompoundInterestRate(
        address _silo,
        uint256 _blockTimestamp,
        bool _usePending
    )
        internal
        view
        virtual
        returns (uint256 rcomp, int96 k)
    {
        ISilo.UtilizationData memory data = ISilo(_silo).utilizationData();

        (rcomp, k) = _getCompoundInterestRate(CompoundInterestRateArgs({
            silo: _silo,
            collateralAssets: data.collateralAssets,
            debtAssets: data.debtAssets,
            interestRateTimestamp: data.interestRateTimestamp,
            blockTimestamp: _blockTimestamp,
            usePending: _usePending
        }));
    }

    function _getCompoundInterestRate(CompoundInterestRateArgs memory _args)
        internal
        view
        virtual
        returns (uint256 rcomp, int96 k)
    {
        (ModelState memory state, Config memory cfg, ImmutableConfig memory immutableCfg) =
            getModelStateAndConfig(_args.usePending);

        require(_args.silo == state.silo, InvalidSilo());

        // k should be set to min on overflow
        if (_args.interestRateTimestamp.wouldOverflowOnCastToInt256()) return (0, cfg.kmin);
        if (_args.blockTimestamp.wouldOverflowOnCastToInt256()) return (0, cfg.kmin);
        if (_args.collateralAssets.wouldOverflowOnCastToInt256()) return (0, cfg.kmin);
        if (_args.debtAssets.wouldOverflowOnCastToInt256()) return (0, cfg.kmin);

        try this.compoundInterestRate({
            _cfg: cfg,
            _state: state,
            _rcompCapPerSecond: immutableCfg.rcompCapPerSecond,
            _t0: int256(uint256(_args.interestRateTimestamp)),
            _t1: int256(_args.blockTimestamp),
            _u: _calculateUtiliation(_args.collateralAssets, _args.debtAssets),
            _tba: int256(_args.debtAssets)
        }) returns (int256 rcompInt, int256 newK) {
            rcomp = SafeCast.toUint256(rcompInt);
            k = _capK(newK, cfg.kmin, cfg.kmax);
        } catch {
            rcomp = 0;
            k = cfg.kmin; // k should be set to min on overflow
        }
    }

    function _getCurrentInterestRate(address _silo, uint256 _blockTimestamp, bool _usePending)
        internal
        view
        virtual
        returns (uint256 rcur)
    {
        (ModelState memory state, Config memory cfg,) = getModelStateAndConfig(_usePending);
        require(_silo == state.silo, InvalidSilo());

        ISilo.UtilizationData memory data = ISilo(state.silo).utilizationData();

        if (data.debtAssets.wouldOverflowOnCastToInt256()) return 0;
        if (_blockTimestamp.wouldOverflowOnCastToInt256()) return 0;

        try this.currentInterestRate({
            _cfg: cfg,
            _state: state,
            _t0: SafeCast.toInt256(data.interestRateTimestamp),
            _t1: int256(_blockTimestamp), // forge-lint: disable-line(unsafe-typecast)
            _u: _calculateUtiliation(data.collateralAssets, data.debtAssets),
            _tba: int256(data.debtAssets) // forge-lint: disable-line(unsafe-typecast)
        }) returns (int256 rcurInt) {
            rcur = SafeCast.toUint256(rcurInt);
        } catch {
            rcur = 0;
        }
    }

    // hard rule: utilization in the model should never be above 100%.
    function _calculateUtiliation(uint256 _collateralAssets, uint256 _debtAssets)
        internal
        pure
        virtual
        returns (int256 u)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        u = int256(SiloMathLib.calculateUtilization(uint256(_DP), _collateralAssets, _debtAssets));
    }

    /// @dev we expect _kmin and _kmax to be in the range of int96
    function _capK(int256 _k, int256 _kmin, int256 _kmax) internal pure virtual returns (int96 cappedK) {
        require(_kmin <= _kmax, InvalidKRange());

        // safe to cast to int96, because we know, that _kmin and _kmax are in the range of int96
        cappedK = int96(SignedMath.max(_kmin, SignedMath.min(_kmax, _k)));
    }
}
