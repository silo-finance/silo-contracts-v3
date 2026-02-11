// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver, IHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";

import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {PartialLiquidationLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationLib.sol";

import {
    PartialLiquidation,
    Rounding,
    SiloMathLib,
    ISiloConfig,
    ISilo,
    IShareToken,
    PartialLiquidationExecLib,
    RevertLib,
    CallBeforeQuoteLib
} from "../liquidation/PartialLiquidation.sol";
import {DefaultingSiloLogic} from "./DefaultingSiloLogic.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

// solhint-disable ordering

/// @title PartialLiquidation module for executing liquidations
/// @dev if we need additional hook functionality, this contract should be included as parent
abstract contract PartialLiquidationByDefaulting is IPartialLiquidationByDefaulting, PartialLiquidation, Whitelist {
    using CallBeforeQuoteLib for ISiloConfig.ConfigData;

    /// @inheritdoc IPartialLiquidationByDefaulting
    uint256 public constant KEEPER_FEE = 0.2e18;

    /// @inheritdoc IPartialLiquidationByDefaulting
    address public immutable LIQUIDATION_LOGIC;

    /// @inheritdoc IPartialLiquidationByDefaulting
    uint256 public constant LT_MARGIN_FOR_DEFAULTING = 0.025e18;

    uint256 internal constant _DECIMALS_PRECISION = 1e18;

    constructor() {
        LIQUIDATION_LOGIC = address(new DefaultingSiloLogic());
    }

    function __PartialLiquidationByDefaulting_init(address _owner) // solhint-disable-line func-name-mixedcase
        internal
        onlyInitializing
        virtual
    {
        __Whitelist_init(_owner);

        validateDefaultingCollateral();
    }
    
    /// @inheritdoc IPartialLiquidationByDefaulting
    function liquidationCallByDefaulting(address _borrower) 
        external 
        virtual
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        (withdrawCollateral, repayDebtAssets) = liquidationCallByDefaulting(_borrower, type(uint256).max);
    }

    /// @inheritdoc IPartialLiquidationByDefaulting
    // solhint-disable-next-line function-max-lines, code-complexity
    function liquidationCallByDefaulting(address _borrower, uint256 _maxDebtToCover)
        public
        virtual
        nonReentrant
        onlyAllowedOrPublic
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        ISiloConfig siloConfigCached = siloConfig;

        require(address(siloConfigCached) != address(0), EmptySiloConfig());

        siloConfigCached.turnOnReentrancyProtection();

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            _fetchConfigs(siloConfigCached, _borrower);

        collateralConfig.lt += LT_MARGIN_FOR_DEFAULTING;

        CallParams memory params;

        (
            params.withdrawAssetsFromCollateral, params.withdrawAssetsFromProtected, repayDebtAssets, params.customError
        ) = PartialLiquidationExecLib.getExactLiquidationAmounts({
            _collateralConfig: collateralConfig,
            _debtConfig: debtConfig,
            _user: _borrower,
            _maxDebtToCover: _maxDebtToCover,
            _liquidationFee: collateralConfig.liquidationFee
        });

        RevertLib.revertIfError(params.customError);

        // calculate split between keeper and lenders
        (params.collateralSharesTotal, params.collateralSharesForKeeper, params.collateralSharesForLenders) =
            _getKeeperAndLenderSharesSplit({
                _silo: collateralConfig.silo,
                _shareToken: collateralConfig.collateralShareToken,
                _liquidationFee: collateralConfig.liquidationFee,
                _assetsToLiquidate: params.withdrawAssetsFromCollateral,
                _collateralType: ISilo.CollateralType.Collateral
            });

        (params.protectedSharesTotal, params.protectedSharesForKeeper, params.protectedSharesForLenders) =
            _getKeeperAndLenderSharesSplit({
                _silo: collateralConfig.silo,
                _shareToken: collateralConfig.protectedShareToken,
                _liquidationFee: collateralConfig.liquidationFee,
                _assetsToLiquidate: params.withdrawAssetsFromProtected,
                _collateralType: ISilo.CollateralType.Protected
            });

        _liquidateByDistributingCollateral({
            _borrower: _borrower,
            _debtSilo: debtConfig.silo,
            _shareToken: collateralConfig.collateralShareToken,
            _withdrawSharesForLenders: params.collateralSharesForLenders,
            _withdrawSharesForKeeper: params.collateralSharesForKeeper
        });

        _liquidateByDistributingCollateral({
            _borrower: _borrower,
            _debtSilo: debtConfig.silo,
            _shareToken: collateralConfig.protectedShareToken,
            _withdrawSharesForLenders: params.protectedSharesForLenders,
            _withdrawSharesForKeeper: params.protectedSharesForKeeper
        });

        // calculate total withdrawn collateral

        if (params.collateralSharesTotal != 0) {
            withdrawCollateral = ISilo(collateralConfig.silo).previewRedeem(
                params.collateralSharesTotal, ISilo.CollateralType.Collateral
            );
        }

        if (params.protectedSharesTotal != 0) {
            withdrawCollateral += ISilo(collateralConfig.silo).previewRedeem(
                params.protectedSharesTotal, ISilo.CollateralType.Protected
            );
        }

        _deductDefaultedDebtFromCollateral(debtConfig.silo, repayDebtAssets);

        siloConfigCached.turnOffReentrancyProtection();

        // settle debt without transferring tokens to silo, by defaulting on debt repayment

        // during actual repay we have conversion assets -> shares -> assets, so we can loose some precision
        // it is possible to deduct 1 wei less from debtTotalAssets than from collateralTotalAssets because of rounding
        (, repayDebtAssets) = _repayDebtByDefaulting(debtConfig.silo, repayDebtAssets, _borrower);

        emit LiquidationCall(msg.sender, debtConfig.silo, _borrower, repayDebtAssets, withdrawCollateral, true);
    }

    function getKeeperAndLenderSharesSplit(
        uint256 _assetsToLiquidate,
        ISilo.CollateralType _collateralType
    ) external view virtual returns (uint256 totalSharesToLiquidate, uint256 keeperShares, uint256 lendersShares) {
        (address silo, address shareToken, uint256 liquidationFee) = _resolveSplitData(_collateralType);

        (totalSharesToLiquidate, keeperShares, lendersShares) = _getKeeperAndLenderSharesSplit({
            _silo: silo,
            _shareToken: shareToken,
            _liquidationFee: liquidationFee,
            _assetsToLiquidate: _assetsToLiquidate,
            _collateralType: _collateralType
        });
    }

    /// @inheritdoc IPartialLiquidationByDefaulting
    function validateControllerForCollateral(address _silo)
        public
        view
        virtual
        returns (ISiloIncentivesController controllerCollateral)
    {
        (, address collateralShareToken,) = siloConfig.getShareTokens(_silo);
        require(collateralShareToken != address(0), EmptyCollateralShareToken());

        controllerCollateral = IGaugeHookReceiver(address(this)).configuredGauges(IShareToken(collateralShareToken));
        require(address(controllerCollateral) != address(0), NoControllerForCollateral());
    }

    /// @inheritdoc IPartialLiquidationByDefaulting
    function validateDefaultingCollateral() public view virtual {
        (address silo0, address silo1) = siloConfig.getSilos();

        ISiloConfig.ConfigData memory config0 = siloConfig.getConfig(silo0);
        ISiloConfig.ConfigData memory config1 = siloConfig.getConfig(silo1);

        require(config0.lt == 0 || config1.lt == 0, TwoWayMarketNotAllowed());

        if (config0.lt == 0) require(config0.liquidationFee == 0, UnnecessaryLiquidationFee());
        else require(config1.liquidationFee == 0, UnnecessaryLiquidationFee());
        
        require(config0.lt + LT_MARGIN_FOR_DEFAULTING < _DECIMALS_PRECISION, InvalidLTConfig0());
        require(config1.lt + LT_MARGIN_FOR_DEFAULTING < _DECIMALS_PRECISION, InvalidLTConfig1());
    }

    function _deductDefaultedDebtFromCollateral(address _silo, uint256 _assetsToRepay) internal virtual {
        bytes memory input =
            abi.encodeWithSelector(DefaultingSiloLogic.deductDefaultedDebtFromCollateral.selector, _assetsToRepay);

        _callOnBehalfOfSilo({
            _silo: ISilo(_silo),
            _calldata: input,
            _errorWhenRevert: DeductDefaultedDebtFromCollateralFailed.selector
        });
    }

    function _repayDebtByDefaulting(address _silo, uint256 _assets, address _borrower) 
        internal 
        virtual 
        returns (uint256 shares, uint256 assets) 
    { 
        (bytes memory data) = _callOnBehalfOfSilo({
            _silo: ISilo(_silo), 
            _calldata: abi.encodeWithSelector(
                DefaultingSiloLogic.repayDebtByDefaulting.selector, _assets, _borrower
            ), 
            _errorWhenRevert: RepayDebtByDefaultingFailed.selector
        });

        (shares, assets) = abi.decode(data, (uint256, uint256));
    }

    function _callOnBehalfOfSilo(ISilo _silo, bytes memory _calldata, bytes4 _errorWhenRevert) 
        internal
        virtual
        returns (bytes memory data) 
    {
        bool success;

        (success, data) = _silo.callOnBehalfOfSilo({
            _target: LIQUIDATION_LOGIC,
            _value: 0,
            _callType: ISilo.CallType.Delegatecall,
            _input: _calldata
        });

        if (!success) RevertLib.revertBytes(data, _errorWhenRevert);
    }

    function _liquidateByDistributingCollateral(
        address _borrower,
        address _debtSilo,
        address _shareToken,
        uint256 _withdrawSharesForLenders,
        uint256 _withdrawSharesForKeeper
    ) internal virtual {
        ISiloIncentivesController controllerCollateral = validateControllerForCollateral(_debtSilo);

        // distribute collateral shares to lenders
        if (_withdrawSharesForLenders > 0) {
            IShareToken(_shareToken).forwardTransferFromNoChecks(
                _borrower, address(controllerCollateral), _withdrawSharesForLenders
            );

            controllerCollateral.immediateDistribution(_shareToken, _withdrawSharesForLenders);
        }

        // distribute collateral shares to keeper
        if (_withdrawSharesForKeeper > 0) {
            IShareToken(_shareToken).forwardTransferFromNoChecks(_borrower, msg.sender, _withdrawSharesForKeeper);
        }
    }

    function _fetchConfigs(ISiloConfig _siloConfigCached, address _borrower)
        internal
        virtual
        returns (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig)
    {
        (collateralConfig, debtConfig) = _siloConfigCached.getConfigsForSolvency(_borrower);

        require(debtConfig.silo != address(0), UserIsSolvent());

        ISilo(debtConfig.silo).accrueInterest();

        if (collateralConfig.silo != debtConfig.silo) {
            ISilo(collateralConfig.silo).accrueInterest();
            collateralConfig.callSolvencyOracleBeforeQuote();
            debtConfig.callSolvencyOracleBeforeQuote();
        }
    }

    // solhint-disable function-max-lines
    function _getKeeperAndLenderSharesSplit(
        address _silo,
        address _shareToken,
        uint256 _liquidationFee,
        uint256 _assetsToLiquidate,
        ISilo.CollateralType _collateralType
    ) internal view virtual returns (uint256 totalSharesToLiquidate, uint256 keeperShares, uint256 lendersShares) {
        if (_assetsToLiquidate == 0) return (0, 0, 0);

        uint256 totalAssets = ISilo(_silo).getTotalAssetsStorage(ISilo.AssetType(uint8(_collateralType)));
        uint256 totalShares = IShareToken(_shareToken).totalSupply();
            
        // assets were calculating with rounding down for withdraw,
        // if we want to go back to shares, we can round up, 
        // however we choose to have exact results as we get via original liquidation, so we are using same direction
        totalSharesToLiquidate = SiloMathLib.convertToShares({
            _assets: _assetsToLiquidate,
            _totalAssets: totalAssets,
            _totalShares: totalShares,
            _rounding: Rounding.LIQUIDATE_TO_SHARES,
            _assetType: ISilo.AssetType(uint8(_collateralType))
        });

        // c - collateral that equals debt value
        // f - liquidation fee
        // CL - total collateral to liquidate
        // kf - keeper fee
        // kp - keeper part
        // D - normalization divider

        // c + c * f = CL
        // c * (1 + f) = CL
        // c = CL / (1 + f)

        // kp = c * f * kf => f * kf * CL / (1 + f)

        // final pseudo code is:

        // kp = f * kf * CL / (1 + f)
        // kp = muldiv(f * kf, CL, (1 + f), R)

        // R - rounding, we want to round down for keeper
        keeperShares = Math.mulDiv(
            _liquidationFee * KEEPER_FEE,
            totalSharesToLiquidate, 
            PartialLiquidationLib._PRECISION_DECIMALS, 
            Math.Rounding.Floor
        ) / (PartialLiquidationLib._PRECISION_DECIMALS + _liquidationFee);

        lendersShares = totalSharesToLiquidate - keeperShares;
    }

    function _resolveSplitData(ISilo.CollateralType _collateralType)
        internal
        view
        virtual
        returns (address silo, address shareToken, uint256 liquidationFee)
    {
        ISiloConfig configCached = siloConfig;
        (address silo0, address silo1) = configCached.getSilos();
        silo = silo0;
        ISiloConfig.ConfigData memory collateralConfig = configCached.getConfig(silo0);

        if (collateralConfig.lt == 0) {
            // if LT is 0, then this can not be collateral, so we pull other config
            collateralConfig = configCached.getConfig(silo1);
            silo = silo1;
        }

        shareToken = _collateralType == ISilo.CollateralType.Collateral
            ? collateralConfig.collateralShareToken
            : collateralConfig.protectedShareToken;

        liquidationFee = collateralConfig.liquidationFee;
    }
}
