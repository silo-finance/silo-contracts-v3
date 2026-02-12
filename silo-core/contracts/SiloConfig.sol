// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "./interfaces/ISilo.sol";
import {ISiloConfig} from "./interfaces/ISiloConfig.sol";
import {CrossReentrancyGuard} from "./utils/CrossReentrancyGuard.sol";
import {Hook} from "./lib/Hook.sol";

/// @notice SiloConfig stores full configuration of Silo in immutable manner
/// @dev Immutable contract is more expensive to deploy than minimal proxy however it provides nearly 10x cheaper
/// data access using immutable variables.
contract SiloConfig is ISiloConfig, CrossReentrancyGuard {
    using Hook for uint256;
    
    uint256 public immutable SILO_ID;

    uint256 internal immutable _DAO_FEE;
    uint256 internal immutable _DEPLOYER_FEE;
    address internal immutable _HOOK_RECEIVER;

    // TOKEN #0

    address internal immutable _SILO0;

    address internal immutable _TOKEN0;

    /// @dev Token that represents a share in total protected deposits of Silo
    address internal immutable _PROTECTED_COLLATERAL_SHARE_TOKEN0;
    /// @dev Token that represents a share in total deposits of Silo
    address internal immutable _COLLATERAL_SHARE_TOKEN0;
    /// @dev Token that represents a share in total debt of Silo
    address internal immutable _DEBT_SHARE_TOKEN0;

    address internal immutable _SOLVENCY_ORACLE0;
    address internal immutable _MAX_LTV_ORACLE0;

    address internal immutable _INTEREST_RATE_MODEL0;

    uint256 internal immutable _MAX_LTV0;
    uint256 internal immutable _LT0;
    /// @dev target LTV after liquidation
    uint256 internal immutable _LIQUIDATION_TARGET_LTV0;
    uint256 internal immutable _LIQUIDATION_FEE0;
    uint256 internal immutable _FLASHLOAN_FEE0;

    bool internal immutable _CALL_BEFORE_QUOTE0;

    // TOKEN #1

    address internal immutable _SILO1;

    address internal immutable _TOKEN1;

    /// @dev Token that represents a share in total protected deposits of Silo
    address internal immutable _PROTECTED_COLLATERAL_SHARE_TOKEN1;
    /// @dev Token that represents a share in total deposits of Silo
    address internal immutable _COLLATERAL_SHARE_TOKEN1;
    /// @dev Token that represents a share in total debt of Silo
    address internal immutable _DEBT_SHARE_TOKEN1;

    address internal immutable _SOLVENCY_ORACLE1;
    address internal immutable _MAX_LTV_ORACLE1;

    address internal immutable _INTEREST_RATE_MODEL1;

    uint256 internal immutable _MAX_LTV1;
    uint256 internal immutable _LT1;
    /// @dev target LTV after liquidation
    uint256 internal immutable _LIQUIDATION_TARGET_LTV1;
    uint256 internal immutable _LIQUIDATION_FEE1;
    uint256 internal immutable _FLASHLOAN_FEE1;

    bool internal immutable _CALL_BEFORE_QUOTE1;
    
    /// @inheritdoc ISiloConfig
    mapping (address borrower => address collateralSilo) public borrowerCollateralSilo;
    
    /// @param _siloId ID of this pool assigned by factory
    /// @param _configData0 silo configuration data for token0
    /// @param _configData1 silo configuration data for token1
    constructor( // solhint-disable-line function-max-lines
        uint256 _siloId,
        ConfigData memory _configData0,
        ConfigData memory _configData1
    ) {
        SILO_ID = _siloId;

        // To make further computations in the Silo secure require DAO and deployer fees to be less than 100%
        require(_configData0.daoFee + _configData0.deployerFee < 1e18, FeeTooHigh());

        _DAO_FEE = _configData0.daoFee;
        _DEPLOYER_FEE = _configData0.deployerFee;
        _HOOK_RECEIVER = _configData0.hookReceiver;

        // TOKEN #0

        _SILO0 = _configData0.silo;
        _TOKEN0 = _configData0.token;

        _PROTECTED_COLLATERAL_SHARE_TOKEN0 = _configData0.protectedShareToken;
        _COLLATERAL_SHARE_TOKEN0 = _configData0.silo;
        _DEBT_SHARE_TOKEN0 = _configData0.debtShareToken;

        _SOLVENCY_ORACLE0 = _configData0.solvencyOracle;
        _MAX_LTV_ORACLE0 = _configData0.maxLtvOracle;

        _INTEREST_RATE_MODEL0 = _configData0.interestRateModel;

        _MAX_LTV0 = _configData0.maxLtv;
        _LT0 = _configData0.lt;
        _LIQUIDATION_TARGET_LTV0 = _configData0.liquidationTargetLtv;
        _LIQUIDATION_FEE0 = _configData0.liquidationFee;
        _FLASHLOAN_FEE0 = _configData0.flashloanFee;

        _CALL_BEFORE_QUOTE0 = _configData0.callBeforeQuote;

        // TOKEN #1

        _SILO1 = _configData1.silo;
        _TOKEN1 = _configData1.token;

        _PROTECTED_COLLATERAL_SHARE_TOKEN1 = _configData1.protectedShareToken;
        _COLLATERAL_SHARE_TOKEN1 = _configData1.silo;
        _DEBT_SHARE_TOKEN1 = _configData1.debtShareToken;

        _SOLVENCY_ORACLE1 = _configData1.solvencyOracle;
        _MAX_LTV_ORACLE1 = _configData1.maxLtvOracle;

        _INTEREST_RATE_MODEL1 = _configData1.interestRateModel;

        _MAX_LTV1 = _configData1.maxLtv;
        _LT1 = _configData1.lt;
        _LIQUIDATION_TARGET_LTV1 = _configData1.liquidationTargetLtv;
        _LIQUIDATION_FEE1 = _configData1.liquidationFee;
        _FLASHLOAN_FEE1 = _configData1.flashloanFee;

        _CALL_BEFORE_QUOTE1 = _configData1.callBeforeQuote;
    }

    /// @inheritdoc ISiloConfig
    function setThisSiloAsCollateralSilo(address) external virtual returns (bool) {
        revert Deprecated();
    }

    /// @inheritdoc ISiloConfig
    function setOtherSiloAsCollateralSilo(address _borrower) external virtual returns (bool collateralSiloChanged) {
        collateralSiloChanged = _setSiloAsCollateralSilo(msg.sender == _SILO0 ? _SILO1 : _SILO0, _borrower);
    }

    /// @inheritdoc ISiloConfig
    function onDebtTransfer(address _sender, address _recipient) external virtual {
        require(msg.sender == _DEBT_SHARE_TOKEN0 || msg.sender == _DEBT_SHARE_TOKEN1, OnlyDebtShareToken());

        address thisSilo = msg.sender == _DEBT_SHARE_TOKEN0 ? _SILO0 : _SILO1;

        require(!hasDebtInOtherSilo(thisSilo, _recipient), DebtExistInOtherSilo());

        if (borrowerCollateralSilo[_recipient] == address(0)) {
            borrowerCollateralSilo[_recipient] = borrowerCollateralSilo[_sender];
        }
    }

    /// @inheritdoc ISiloConfig
    function accrueInterestForSilo(address _silo) external virtual {
        address irm;

        if (_silo == _SILO0) {
            irm = _INTEREST_RATE_MODEL0;
        } else if (_silo == _SILO1) {
            irm = _INTEREST_RATE_MODEL1;
        } else {
            revert WrongSilo();
        }

        ISilo(_silo).accrueInterestForConfig(
            irm,
            _DAO_FEE,
            _DEPLOYER_FEE
        );
    }

    /// @inheritdoc ISiloConfig
    function accrueInterestForBothSilos() external virtual {
        ISilo(_SILO0).accrueInterestForConfig(
            _INTEREST_RATE_MODEL0,
            _DAO_FEE,
            _DEPLOYER_FEE
        );

        ISilo(_SILO1).accrueInterestForConfig(
            _INTEREST_RATE_MODEL1,
            _DAO_FEE,
            _DEPLOYER_FEE
        );
    }

    /// @inheritdoc ISiloConfig
    function getConfigsForSolvency(address _borrower) public view virtual returns (
        ConfigData memory collateralConfig,
        ConfigData memory debtConfig
    ) {
        address debtSilo = getDebtSilo(_borrower);

        if (debtSilo == address(0)) return (collateralConfig, debtConfig);

        address collateralSilo = borrowerCollateralSilo[_borrower];

        collateralConfig = getConfig(collateralSilo);
        debtConfig = getConfig(debtSilo);
    }

    /// @inheritdoc ISiloConfig
    // solhint-disable-next-line ordering
    function getConfigsForWithdraw(address _silo, address _depositOwner) external view virtual returns (
        DepositConfig memory depositConfig,
        ConfigData memory collateralConfig,
        ConfigData memory debtConfig
    ) {
        depositConfig = _getDepositConfig(_silo);
        (collateralConfig, debtConfig) = getConfigsForSolvency(_depositOwner);
    }

    /// @inheritdoc ISiloConfig
    function getConfigsForBorrow(address _debtSilo)
        external
        view
        virtual
        returns (ConfigData memory collateralConfig, ConfigData memory debtConfig)
    {
        address collateralSilo; 
        
        if (_debtSilo == _SILO0) {
            collateralSilo = _SILO1;
        } else if (_debtSilo == _SILO1) {
            collateralSilo = _SILO0;
        } else {
            revert WrongSilo();
        }

        collateralConfig = getConfig(collateralSilo);
        debtConfig = getConfig(_debtSilo);
    }

    /// @inheritdoc ISiloConfig
    function getSilos() external view virtual returns (address silo0, address silo1) {
        return (_SILO0, _SILO1);
    }

    /// @inheritdoc ISiloConfig
    function getShareTokens(address _silo)
        external
        view
        virtual
        returns (address protectedShareToken, address collateralShareToken, address debtShareToken)
    {
        if (_silo == _SILO0) {
            return (_PROTECTED_COLLATERAL_SHARE_TOKEN0, _COLLATERAL_SHARE_TOKEN0, _DEBT_SHARE_TOKEN0);
        } else if (_silo == _SILO1) {
            return (_PROTECTED_COLLATERAL_SHARE_TOKEN1, _COLLATERAL_SHARE_TOKEN1, _DEBT_SHARE_TOKEN1);
        } else {
            revert WrongSilo();
        }
    }

    /// @inheritdoc ISiloConfig
    function getAssetForSilo(address _silo) external view virtual returns (address asset) {
        if (_silo == _SILO0) {
            return _TOKEN0;
        } else if (_silo == _SILO1) {
            return _TOKEN1;
        } else {
            revert WrongSilo();
        }
    }

    /// @inheritdoc ISiloConfig
    function getFeesWithAsset(address _silo)
        external
        view
        virtual
        returns (uint256 daoFee, uint256 deployerFee, uint256 flashloanFee, address asset)
    {
        daoFee = _DAO_FEE;
        deployerFee = _DEPLOYER_FEE;

        if (_silo == _SILO0) {
            asset = _TOKEN0;
            flashloanFee = _FLASHLOAN_FEE0;
        } else if (_silo == _SILO1) {
            asset = _TOKEN1;
            flashloanFee = _FLASHLOAN_FEE1;
        } else {
            revert WrongSilo();
        }
    }

    /// @inheritdoc ISiloConfig
    function getCollateralShareTokenAndAsset(address _silo, ISilo.CollateralType _collateralType)
        external
        view
        virtual
        returns (address shareToken, address asset)
    {
        if (_silo == _SILO0) {
            return _collateralType == ISilo.CollateralType.Collateral
                ? (_COLLATERAL_SHARE_TOKEN0, _TOKEN0)
                : (_PROTECTED_COLLATERAL_SHARE_TOKEN0, _TOKEN0);
        } else if (_silo == _SILO1) {
            return _collateralType == ISilo.CollateralType.Collateral
                ? (_COLLATERAL_SHARE_TOKEN1, _TOKEN1)
                : (_PROTECTED_COLLATERAL_SHARE_TOKEN1, _TOKEN1);
        } else {
            revert WrongSilo();
        }
    }

    /// @inheritdoc ISiloConfig
    function getDebtShareTokenAndAsset(address _silo)
        external
        view
        virtual
        returns (address shareToken, address asset)
    {
        if (_silo == _SILO0) {
            return (_DEBT_SHARE_TOKEN0, _TOKEN0);
        } else if (_silo == _SILO1) {
            return (_DEBT_SHARE_TOKEN1, _TOKEN1);
        } else {
            revert WrongSilo();
        }
    }

    /// @inheritdoc ISiloConfig
    function getConfig(address _silo) public view virtual returns (ConfigData memory config) {
        if (_silo == _SILO0) {
            config = _silo0ConfigData();
        } else if (_silo == _SILO1) {
            config = _silo1ConfigData();
        } else {
            revert WrongSilo();
        }
    }

    /// @inheritdoc ISiloConfig
    function hasDebtInOtherSilo(address _thisSilo, address _borrower) public view virtual returns (bool hasDebt) {
        if (_thisSilo == _SILO0) {
            hasDebt = _balanceOf(_DEBT_SHARE_TOKEN1, _borrower) != 0;
        } else if (_thisSilo == _SILO1) {
            hasDebt = _balanceOf(_DEBT_SHARE_TOKEN0, _borrower) != 0;
        } else {
            revert WrongSilo();
        }
     }

    /// @inheritdoc ISiloConfig
    function getDebtSilo(address _borrower) public view virtual returns (address debtSilo) {
        uint256 debtBal0 = _balanceOf(_DEBT_SHARE_TOKEN0, _borrower);
        uint256 debtBal1 = _balanceOf(_DEBT_SHARE_TOKEN1, _borrower);

        require(debtBal0 == 0 || debtBal1 == 0, DebtExistInOtherSilo());
        if (debtBal0 == 0 && debtBal1 == 0) return address(0);

        debtSilo = debtBal0 != 0 ? _SILO0 : _SILO1;
    }

    function _silo0ConfigData() internal view virtual returns (ConfigData memory config) {
        config = ConfigData({
            daoFee: _DAO_FEE,
            deployerFee: _DEPLOYER_FEE,
            silo: _SILO0,
            token: _TOKEN0,
            protectedShareToken: _PROTECTED_COLLATERAL_SHARE_TOKEN0,
            collateralShareToken: _COLLATERAL_SHARE_TOKEN0,
            debtShareToken: _DEBT_SHARE_TOKEN0,
            solvencyOracle: _SOLVENCY_ORACLE0,
            maxLtvOracle: _MAX_LTV_ORACLE0,
            interestRateModel: _INTEREST_RATE_MODEL0,
            maxLtv: _MAX_LTV0,
            lt: _LT0,
            liquidationTargetLtv: _LIQUIDATION_TARGET_LTV0,
            liquidationFee: _LIQUIDATION_FEE0,
            flashloanFee: _FLASHLOAN_FEE0,
            hookReceiver: _HOOK_RECEIVER,
            callBeforeQuote: _CALL_BEFORE_QUOTE0
        });
    }

    function _silo1ConfigData() internal view virtual returns (ConfigData memory config) {
        config = ConfigData({
            daoFee: _DAO_FEE,
            deployerFee: _DEPLOYER_FEE,
            silo: _SILO1,
            token: _TOKEN1,
            protectedShareToken: _PROTECTED_COLLATERAL_SHARE_TOKEN1,
            collateralShareToken: _COLLATERAL_SHARE_TOKEN1,
            debtShareToken: _DEBT_SHARE_TOKEN1,
            solvencyOracle: _SOLVENCY_ORACLE1,
            maxLtvOracle: _MAX_LTV_ORACLE1,
            interestRateModel: _INTEREST_RATE_MODEL1,
            maxLtv: _MAX_LTV1,
            lt: _LT1,
            liquidationTargetLtv: _LIQUIDATION_TARGET_LTV1,
            liquidationFee: _LIQUIDATION_FEE1,
            flashloanFee: _FLASHLOAN_FEE1,
            hookReceiver: _HOOK_RECEIVER,
            callBeforeQuote: _CALL_BEFORE_QUOTE1
        });
    }

    function _getDepositConfig(address _silo) internal view virtual returns (DepositConfig memory config) {
        if (_silo == _SILO0) {
            config = DepositConfig({
                silo: _SILO0,
                token: _TOKEN0,
                collateralShareToken: _COLLATERAL_SHARE_TOKEN0,
                protectedShareToken: _PROTECTED_COLLATERAL_SHARE_TOKEN0,
                daoFee: _DAO_FEE,
                deployerFee: _DEPLOYER_FEE,
                interestRateModel: _INTEREST_RATE_MODEL0
            });
        } else if (_silo == _SILO1) {
            config = DepositConfig({
                silo: _SILO1,
                token: _TOKEN1,
                collateralShareToken: _COLLATERAL_SHARE_TOKEN1,
                protectedShareToken: _PROTECTED_COLLATERAL_SHARE_TOKEN1,
                daoFee: _DAO_FEE,
                deployerFee: _DEPLOYER_FEE,
                interestRateModel: _INTEREST_RATE_MODEL1
            });
        } else {
            revert WrongSilo();
        }
    }

    function _onlySiloOrTokenOrHookReceiver() internal view virtual override {
        if (msg.sender != _SILO0 &&
            msg.sender != _SILO1 &&
            msg.sender != _HOOK_RECEIVER &&
            msg.sender != _COLLATERAL_SHARE_TOKEN0 &&
            msg.sender != _COLLATERAL_SHARE_TOKEN1 &&
            msg.sender != _PROTECTED_COLLATERAL_SHARE_TOKEN0 &&
            msg.sender != _PROTECTED_COLLATERAL_SHARE_TOKEN1 &&
            msg.sender != _DEBT_SHARE_TOKEN0 &&
            msg.sender != _DEBT_SHARE_TOKEN1
        ) {
            revert OnlySiloOrTokenOrHookReceiver();
        }
    }

    function _onlySilo() internal view virtual {
        require(msg.sender == _SILO0 || msg.sender == _SILO1, OnlySilo());
    }

    function _balanceOf(address _token, address _user) internal view virtual returns (uint256 balance) {
        balance = IERC20(_token).balanceOf(_user);
    }

    function _setSiloAsCollateralSilo(address _newCollateralSilo, address _borrower)
        internal
        virtual
        returns (bool collateralSiloChanged)
    {
        _onlySilo();

        if (borrowerCollateralSilo[_borrower] != _newCollateralSilo) {
            borrowerCollateralSilo[_borrower] = _newCollateralSilo;
            collateralSiloChanged = true;
        }
    }
}
