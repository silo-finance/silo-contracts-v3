// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {Ownable1and2Steps} from "common/access/Ownable1and2Steps.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";
import {IInterestRateModelV2Factory} from "silo-core/contracts/interfaces/IInterestRateModelV2Factory.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";
import {
    ISiloIncentivesControllerFactory
} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {Views} from "silo-core/contracts/lib/Views.sol";

/// @notice Silo Deployer
contract SiloDeployer is Create2Factory, ISiloDeployer {
    // solhint-disable var-name-mixedcase
    IInterestRateModelV2Factory public immutable IRM_CONFIG_FACTORY;
    IDynamicKinkModelFactory public immutable DYNAMIC_KINK_MODEL_FACTORY;
    ISiloFactory public immutable SILO_FACTORY;
    ISiloIncentivesControllerFactory public immutable SILO_INCENTIVES_CONTROLLER_FACTORY;
    address public immutable SILO_IMPL;
    address public immutable SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL;
    address public immutable SHARE_DEBT_TOKEN_IMPL;
    // solhint-enable var-name-mixedcase

    /// @notice variable to store the final hook owner
    address internal transient _finalHookOwner;

    /// @notice TRUE is hook has defaulting liquidation
    bool internal transient _gaugeRequired;

    constructor(
        IInterestRateModelV2Factory _irmConfigFactory,
        IDynamicKinkModelFactory _dynamicKinkModelFactory,
        ISiloFactory _siloFactory,
        ISiloIncentivesControllerFactory _siloIncentivesControllerFactory,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl
    ) {
        IRM_CONFIG_FACTORY = _irmConfigFactory;
        DYNAMIC_KINK_MODEL_FACTORY = _dynamicKinkModelFactory;
        SILO_FACTORY = _siloFactory;
        SILO_INCENTIVES_CONTROLLER_FACTORY = _siloIncentivesControllerFactory;
        SILO_IMPL = _siloImpl;
        SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL = _shareProtectedCollateralTokenImpl;
        SHARE_DEBT_TOKEN_IMPL = _shareDebtTokenImpl;
    }

    /// @inheritdoc ISiloDeployer
    function deploy(
        Oracles calldata _oracles,
        bytes calldata _irmConfigData0,
        bytes calldata _irmConfigData1,
        ClonableHookReceiver calldata _clonableHookReceiver,
        ISiloConfig.InitData memory _siloInitData
    ) external returns (ISiloConfig siloConfig) {
        // setUp IRMs (create if needed) and update `_siloInitData`
        _setUpIRMs(_irmConfigData0, _irmConfigData1, _siloInitData);
        // create oracles and update `_siloInitData`
        _createOracles(_siloInitData, _oracles);
        // clone hook receiver if needed
        _cloneHookReceiver(_siloInitData, _clonableHookReceiver.implementation);
        // deploy `SiloConfig` (with predicted addresses)
        siloConfig = _deploySiloConfig(_siloInitData);
        // create silo
        SILO_FACTORY.createSilo({
            _siloConfig: siloConfig,
            _siloImpl: SILO_IMPL,
            _shareProtectedCollateralTokenImpl: SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL,
            _shareDebtTokenImpl: SHARE_DEBT_TOKEN_IMPL,
            _deployer: _siloInitData.deployer,
            _creator: msg.sender
        });

        _gaugeRequired = _isDefaultingHook(_siloInitData.hookReceiver);

        // initialize hook receiver only if it was cloned
        _initializeHookReceiver(_siloInitData, siloConfig, _clonableHookReceiver);

        _createIncentivesController(siloConfig, _siloInitData);

        emit SiloCreated(siloConfig);
    }

    /// @notice Create an incentives controller if the hook is defaulting
    function _createIncentivesController(ISiloConfig _siloConfig, ISiloConfig.InitData memory _siloInitData)
        internal
    {
        if (!_gaugeRequired) return;

        address debtSilo = _getDebtSilo(_siloConfig, _siloInitData);

        address incentivesController = SILO_INCENTIVES_CONTROLLER_FACTORY.create({
            _owner: _finalHookOwner,
            _notifier: _siloInitData.hookReceiver,
            _shareToken: debtSilo,
            _externalSalt: bytes32(0)
        });

        IGaugeHookReceiver(_siloInitData.hookReceiver).setGauge({
            _gauge: ISiloIncentivesController(incentivesController), 
            _shareToken: IShareToken(debtSilo)
        });

        Ownable1and2Steps(_siloInitData.hookReceiver).transferOwnership1Step(_finalHookOwner);
    }

    function _isDefaultingHook(address _hook) internal view returns (bool isDefaulting) {
        // in forge we can have code length 1
        if (_hook.code.length < 32) return false;

        try IPartialLiquidationByDefaulting(_hook).LT_MARGIN_FOR_DEFAULTING() returns (uint256 margin) {
            return margin != 0;
        } catch {
            return false;
        }
    }

    function _getDebtSilo(ISiloConfig _siloConfig, ISiloConfig.InitData memory _siloInitData)
        internal
        view
        returns (address debtSilo)
    {
        (address silo0, address silo1) = _siloConfig.getSilos();
        debtSilo = _siloInitData.lt0 == 0 ? silo0 : silo1;
    }

    /// @notice Deploy `SiloConfig` with predicted addresses
    /// @param _siloInitData Silo configuration for the silo creation
    /// @return siloConfig Deployed `SiloConfig`
    // solhint-disable-next-line function-max-lines
    function _deploySiloConfig(ISiloConfig.InitData memory _siloInitData) internal returns (ISiloConfig siloConfig) {
        uint256 creatorSiloCounter = SILO_FACTORY.creatorSiloCounter(msg.sender);

        ISiloConfig.ConfigData memory configData0;
        ISiloConfig.ConfigData memory configData1;

        (configData0, configData1) = Views.copySiloConfig({
            _initData: _siloInitData,
            _daoFeeRange: SILO_FACTORY.daoFeeRange(),
            _maxDeployerFee: SILO_FACTORY.maxDeployerFee(),
            _maxFlashloanFee: SILO_FACTORY.maxFlashloanFee(),
            _maxLiquidationFee: SILO_FACTORY.maxLiquidationFee()
        });

        configData0.silo = CloneDeterministic.predictSilo0Addr({
            _siloImpl: SILO_IMPL,
            _creatorSiloCounter: creatorSiloCounter,
            _deployer: address(SILO_FACTORY),
            _creator: msg.sender
        });

        configData1.silo = CloneDeterministic.predictSilo1Addr({
            _siloImpl: SILO_IMPL,
            _creatorSiloCounter: creatorSiloCounter,
            _deployer: address(SILO_FACTORY),
            _creator: msg.sender
        });

        configData0.collateralShareToken = configData0.silo;
        configData1.collateralShareToken = configData1.silo;

        configData0.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken0Addr({
            _shareProtectedCollateralTokenImpl: SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL,
            _creatorSiloCounter: creatorSiloCounter,
            _deployer: address(SILO_FACTORY),
            _creator: msg.sender
        });

        configData1.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken1Addr({
            _shareProtectedCollateralTokenImpl: SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL,
            _creatorSiloCounter: creatorSiloCounter,
            _deployer: address(SILO_FACTORY),
            _creator: msg.sender
        });

        configData0.debtShareToken = CloneDeterministic.predictShareDebtToken0Addr({
            _shareDebtTokenImpl: SHARE_DEBT_TOKEN_IMPL,
            _creatorSiloCounter: creatorSiloCounter,
            _deployer: address(SILO_FACTORY),
            _creator: msg.sender
        });

        configData1.debtShareToken = CloneDeterministic.predictShareDebtToken1Addr({
            _shareDebtTokenImpl: SHARE_DEBT_TOKEN_IMPL,
            _creatorSiloCounter: creatorSiloCounter,
            _deployer: address(SILO_FACTORY),
            _creator: msg.sender
        });

        uint256 nextSiloId = SILO_FACTORY.getNextSiloId();

        siloConfig = ISiloConfig(address(new SiloConfig{salt: _salt()}(nextSiloId, configData0, configData1)));
    }

    /// @notice Create IRMs and update `_siloInitData`
    /// @param _irmConfigData0 IRM config data for a silo `_TOKEN0`
    /// @param _irmConfigData1 IRM config data for a silo `_TOKEN1`
    /// @param _siloInitData Silo configuration for the silo creation
    function _setUpIRMs(
        bytes calldata _irmConfigData0,
        bytes calldata _irmConfigData1,
        ISiloConfig.InitData memory _siloInitData
    ) internal {
        bytes32 salt = _salt();

        if (_siloInitData.interestRateModel0 == address(IRM_CONFIG_FACTORY)) {
            _siloInitData.interestRateModel0 = _createInterestRateModel(_irmConfigData0, salt);
        }

        if (_siloInitData.interestRateModel1 == address(IRM_CONFIG_FACTORY)) {
            _siloInitData.interestRateModel1 = _createInterestRateModel(_irmConfigData1, salt);
        }

        uint256 creatorSiloCounter = SILO_FACTORY.creatorSiloCounter(msg.sender);

        if (_siloInitData.interestRateModel0 == address(DYNAMIC_KINK_MODEL_FACTORY)) {
            address silo = CloneDeterministic.predictSilo0Addr({
                _siloImpl: SILO_IMPL,
                _creatorSiloCounter: creatorSiloCounter,
                _deployer: address(SILO_FACTORY),
                _creator: msg.sender
            });

            _siloInitData.interestRateModel0 = _createDKinkIRM(_irmConfigData0, silo, salt);
        }

        if (_siloInitData.interestRateModel1 == address(DYNAMIC_KINK_MODEL_FACTORY)) {
            address silo = CloneDeterministic.predictSilo1Addr({
                _siloImpl: SILO_IMPL,
                _creatorSiloCounter: creatorSiloCounter,
                _deployer: address(SILO_FACTORY),
                _creator: msg.sender
            });

            _siloInitData.interestRateModel1 = _createDKinkIRM(_irmConfigData1, silo, salt);
        }
    }

    /// @notice Create an interest rate model
    /// @param _irmConfigData IRM config data
    /// @return interestRateModel Deployed interest rate model
    function _createInterestRateModel(bytes memory _irmConfigData, bytes32 _salt) internal returns (address) {
        IInterestRateModelV2.Config memory config = abi.decode(_irmConfigData, (IInterestRateModelV2.Config));
        (, IInterestRateModelV2 interestRateModel) = IRM_CONFIG_FACTORY.create(config, _salt);

        return address(interestRateModel);
    }

    /// @notice Create a DKinkIRM
    /// @param _irmConfigData DKinkIRM config data
    /// @param _silo Silo address
    /// @return interestRateModel Deployed DKinkIRM
    function _createDKinkIRM(bytes memory _irmConfigData, address _silo, bytes32 _salt) internal returns (address) {
        DKinkIRMConfig memory dkink = abi.decode(_irmConfigData, (DKinkIRMConfig));

        IInterestRateModel interestRateModel = DYNAMIC_KINK_MODEL_FACTORY.create({
            _config: dkink.config,
            _immutableArgs: dkink.immutableArgs,
            _initialOwner: dkink.initialOwner,
            _silo: _silo,
            _externalSalt: _salt
        });

        return address(interestRateModel);
    }

    /// @notice Create an oracle if it is not specified in the `_siloInitData` and has tx details for the creation
    /// @param _siloInitData Silo configuration for the silo creation
    /// @param _oracles Oracles creation details (factory and creation tx input)
    function _createOracles(ISiloConfig.InitData memory _siloInitData, Oracles memory _oracles) internal {
        if (_siloInitData.solvencyOracle0 == address(0)) {
            _siloInitData.solvencyOracle0 = _createOracle(_oracles.solvencyOracle0);
        }

        if (_siloInitData.maxLtvOracle0 == address(0)) {
            _siloInitData.maxLtvOracle0 = _createOracle(_oracles.maxLtvOracle0);
        }

        if (_siloInitData.solvencyOracle1 == address(0)) {
            _siloInitData.solvencyOracle1 = _createOracle(_oracles.solvencyOracle1);
        }

        if (_siloInitData.maxLtvOracle1 == address(0)) {
            _siloInitData.maxLtvOracle1 = _createOracle(_oracles.maxLtvOracle1);
        }
    }

    /// @notice Create an oracle
    /// @param _txData Oracle creation details (factory and creation tx input)
    function _createOracle(OracleCreationTxData memory _txData) internal returns (address _oracle) {
        if (_txData.deployed != address(0)) return _txData.deployed;

        address factory = _txData.factory;

        if (factory == address(0)) return address(0);

        _updateSalt(_txData.txInput);

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = factory.call(_txData.txInput);

        require(success && data.length == 32, FailedToCreateAnOracle(factory));

        // Safe: `data` length is exactly 32 bytes and encodes an EVM address in the low 20 bytes.
        // forge-lint: disable-next-line(unsafe-typecast)
        _oracle = address(uint160(uint256(bytes32(data))));
    }

    /// @notice Clone hook receiver if it is provided
    /// @param _siloInitData Silo configuration for the silo creation
    /// @param _hookReceiverImplementation Hook receiver implementation to clone
    function _cloneHookReceiver(ISiloConfig.InitData memory _siloInitData, address _hookReceiverImplementation)
        internal
    {
        require(
            _hookReceiverImplementation == address(0) || _siloInitData.hookReceiver == address(0),
            HookReceiverMisconfigured()
        );

        if (_hookReceiverImplementation != address(0)) {
            _siloInitData.hookReceiver = Clones.cloneDeterministic(_hookReceiverImplementation, _salt());
        }
    }

    /// @notice Initialize hook receiver if it was cloned
    /// @param _siloInitData Silo configuration for the silo creation
    /// (where _siloInitData.hookReceiver is the cloned hook receiver)
    /// @param _siloConfig Configuration of the created silo
    /// @param _clonableHookReceiver Hook receiver implementation and initialization data
    function _initializeHookReceiver(
        ISiloConfig.InitData memory _siloInitData,
        ISiloConfig _siloConfig,
        ClonableHookReceiver calldata _clonableHookReceiver
    ) internal {
        if (_clonableHookReceiver.implementation != address(0)) {
            (_finalHookOwner) = abi.decode(_clonableHookReceiver.initializationData, (address));

            IHookReceiver(_siloInitData.hookReceiver)
                .initialize({
                    _siloConfig: _siloConfig,
                    // override owner so we can set the incentives controller
                    _data: _gaugeRequired ? abi.encode(address(this)) : _clonableHookReceiver.initializationData
                });
        }
    }

    /// @notice Update the salt of the tx input
    /// @param _txInput The tx input for the oracle factory
    function _updateSalt(bytes memory _txInput) internal {
        bytes32 salt = _salt();

        assembly {
            // solhint-disable-line no-inline-assembly
            let pointer := add(add(_txInput, 0x20), sub(mload(_txInput), 0x20))
            mstore(pointer, salt)
        }
    }
}
