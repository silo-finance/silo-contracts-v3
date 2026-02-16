// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {ERC721} from "openzeppelin5/token/ERC721/ERC721.sol";

import {IShareTokenInitializable} from "./interfaces/IShareTokenInitializable.sol";
import {ISiloFactory} from "./interfaces/ISiloFactory.sol";
import {ISilo} from "./interfaces/ISilo.sol";
import {IShareToken} from "./interfaces/IShareToken.sol";
import {ISiloConfig, SiloConfig} from "./SiloConfig.sol";
import {Hook} from "./lib/Hook.sol";
import {Views} from "./lib/Views.sol";
import {CloneDeterministic} from "./lib/CloneDeterministic.sol";
import {IVersioned} from "./interfaces/IVersioned.sol";

contract SiloFactory is ISiloFactory, ERC721, Ownable2Step, IVersioned {
    /// @dev max fee is 50%, 1e18 == 100%
    uint256 public constant MAX_FEE = 0.5e18;

    /// @dev max percent is 1e18 == 100%
    uint256 public constant MAX_PERCENT = 1e18;

    /// @dev dao fee range (min, max) in 18 decimals, 1e18 == 100%
    Range private _daoFeeRange;
    uint256 public maxDeployerFee;
    uint256 public maxFlashloanFee;
    uint256 public maxLiquidationFee;

    /// @dev default DAO fee receiver, will be used in case there is nothing set per silo or per asset
    address public daoFeeReceiver;

    string public baseURI;

    mapping(uint256 id => address siloConfig) public idToSiloConfig;
    mapping(address silo => bool) public isSilo;

    /// @dev DAO fee receiver for silo, it has biggest priority over other setup for DAO fee receiver
    mapping(address silo => address feeReceiverPerSilo) public siloDaoFeeReceivers;

    /// @dev DAO fee receiver for asset, in case there is no setup for silo, this setup will be used
    mapping(address asset => address feeReceiverPerAsset) public assetDaoFeeReceivers;

    /// @dev counter of silos created by the wallet
    mapping(address creator => uint256 siloCounter) public creatorSiloCounter;

    uint256 internal _siloId;

    constructor(address _daoFeeReceiver)
        ERC721("Silo Finance Fee Receiver", "feeSILO")
        Ownable(msg.sender)
    {
        _siloId = 3000;

        baseURI = "https://v2.app.silo.finance/markets/";
        emit BaseURI(baseURI);

        _setDaoFee({_minFee: 0.05e18, _maxFee: 0.5e18});
        _setDaoFeeReceiver(_daoFeeReceiver);

        _setMaxDeployerFee({_newMaxDeployerFee: 0.15e18}); // 15% max deployer fee
        _setMaxFlashloanFee({_newMaxFlashloanFee: 0.15e18}); // 15% max flashloan fee
        _setMaxLiquidationFee({_newMaxLiquidationFee: 0.30e18}); // 30% max liquidation fee
    }

    /// @inheritdoc ISiloFactory
    function createSilo( // solhint-disable-line function-max-lines
        ISiloConfig _siloConfig,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl,
        address _deployer,
        address _creator
    )
        external
        virtual
    {
        require(
            _siloImpl != address(0) &&
            _shareProtectedCollateralTokenImpl != address(0) &&
            _shareDebtTokenImpl != address(0) &&
            address(_siloConfig) != address(0),
            ZeroAddress()
        );

        uint256 nextSiloId = _siloId;
        // safe to uncheck, because we will not create 2 ** 256 of silos in a lifetime
        unchecked { _siloId++; }

        (ISilo silo0, ISilo silo1) = _createValidateSilosAndShareTokens(
            _siloConfig,
            _siloImpl,
            _shareProtectedCollateralTokenImpl,
            _shareDebtTokenImpl,
            _creator
        );

        unchecked { creatorSiloCounter[_creator]++; }

        silo0.initialize(_siloConfig);
        silo1.initialize(_siloConfig);

        _initializeShareTokens(_siloConfig, silo0, silo1);

        silo0.updateHooks();
        silo1.updateHooks();

        idToSiloConfig[nextSiloId] = address(_siloConfig);

        isSilo[address(silo0)] = true;
        isSilo[address(silo1)] = true;

        if (_deployer != address(0)) {
            _safeMint(_deployer, nextSiloId);
        }

        emit NewSilo(
            _siloImpl,
            silo0.asset(),
            silo1.asset(),
            address(silo0),
            address(silo1),
            address(_siloConfig)
        );

        _emitEventAboutSiloContracts(_siloConfig, silo0);
        _emitEventAboutSiloContracts(_siloConfig, silo1);
    }

    /// @inheritdoc ISiloFactory
    function burn(uint256 _siloIdToBurn) external virtual {
        require(msg.sender == _ownerOf(_siloIdToBurn), NotYourSilo());

        _burn(_siloIdToBurn);
    }

    /// @inheritdoc ISiloFactory
    function setDaoFee(uint128 _minFee, uint128 _maxFee) external virtual onlyOwner {
        _setDaoFee(_minFee, _maxFee);
    }

    /// @inheritdoc ISiloFactory
    function setMaxDeployerFee(uint256 _newMaxDeployerFee) external virtual onlyOwner {
        _setMaxDeployerFee(_newMaxDeployerFee);
    }

    /// @inheritdoc ISiloFactory
    function setMaxFlashloanFee(uint256 _newMaxFlashloanFee) external virtual onlyOwner {
        _setMaxFlashloanFee(_newMaxFlashloanFee);
    }

    /// @inheritdoc ISiloFactory
    function setMaxLiquidationFee(uint256 _newMaxLiquidationFee) external virtual onlyOwner {
        _setMaxLiquidationFee(_newMaxLiquidationFee);
    }

    /// @inheritdoc ISiloFactory
    function setDaoFeeReceiver(address _newDaoFeeReceiver) external virtual onlyOwner {
        _setDaoFeeReceiver(_newDaoFeeReceiver);
    }

    /// @inheritdoc ISiloFactory
    function setDaoFeeReceiverForAsset(address _asset, address _newDaoFeeReceiver) external virtual onlyOwner {
        _setDaoFeeReceiver(assetDaoFeeReceivers, _asset, _newDaoFeeReceiver);
        emit DaoFeeReceiverChangedForSilo(_asset, _newDaoFeeReceiver);
    }

    /// @inheritdoc ISiloFactory
    function setDaoFeeReceiverForSilo(address _silo, address _newDaoFeeReceiver) external virtual onlyOwner {
        _setDaoFeeReceiver(siloDaoFeeReceivers, _silo, _newDaoFeeReceiver);
        emit DaoFeeReceiverChangedForSilo(_silo, _newDaoFeeReceiver);
    }

    /// @inheritdoc ISiloFactory
    function setBaseURI(string calldata _newBaseURI) external virtual onlyOwner {
        baseURI = _newBaseURI;
        emit BaseURI(_newBaseURI);
    }

    /// @inheritdoc ISiloFactory
    function getNextSiloId() external view virtual returns (uint256) {
        return _siloId;
    }

    function daoFeeRange() external view virtual returns (Range memory) {
        return _daoFeeRange;
    }

    /// @inheritdoc ISiloFactory
    function getFeeReceivers(address _silo)
        external
        view
        virtual
        returns (address daoReceiver, address deployerReceiver)
    {
        uint256 siloID = ISilo(_silo).config().SILO_ID();

        daoReceiver = siloDaoFeeReceivers[_silo];
        if (daoReceiver == address(0)) daoReceiver = assetDaoFeeReceivers[ISilo(_silo).asset()];
        if (daoReceiver == address(0)) daoReceiver = daoFeeReceiver;

        deployerReceiver = _ownerOf(siloID);
    }

    /// @inheritdoc ISiloFactory
    function validateSiloInitData(ISiloConfig.InitData memory _initData) external view virtual returns (bool) {
        return Views.validateSiloInitData(_initData, _daoFeeRange, maxDeployerFee, maxFlashloanFee, maxLiquidationFee);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "SiloFactory 4.0.0";
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);

        return string.concat(
            baseURI,
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(idToSiloConfig[tokenId])
        );
    }

    function _emitEventAboutSiloContracts(ISiloConfig _siloConfig, ISilo _silo) internal virtual {
        (
            address protectedShareToken, address collateralShareToken, address debtShareToken
        ) = _siloConfig.getShareTokens(address(_silo));

        emit NewSiloShareTokens(protectedShareToken, collateralShareToken, debtShareToken);
        emit NewSiloHook(address(_silo), IShareToken(address(_silo)).hookReceiver());
    }

    function _createValidateSilosAndShareTokens(
        ISiloConfig _siloConfig,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl,
        address _creator
    ) internal virtual returns (ISilo silo0, ISilo silo1) {
        uint256 counter = creatorSiloCounter[_creator];

        silo0 = ISilo(CloneDeterministic.silo0(_siloImpl, counter, _creator));
        silo1 = ISilo(CloneDeterministic.silo1(_siloImpl, counter, _creator));

        (address siloFromConfig0, address siloFromConfig1) = _siloConfig.getSilos();

        require(address(silo0) == siloFromConfig0 && address(silo1) == siloFromConfig1, ConfigMismatchSilo());

        _cloneShareTokensAndValidate(
            _siloConfig,
            silo0,
            silo1,
            _shareProtectedCollateralTokenImpl,
            _shareDebtTokenImpl,
            counter,
            _creator
        );
    }

    function _setDaoFee(uint128 _minFee, uint128 _maxFee) internal virtual {
        require(_maxFee <= MAX_FEE, MaxFeeExceeded());
        require(_minFee <= _maxFee, InvalidFeeRange());
        require(_daoFeeRange.min != _minFee || _daoFeeRange.max != _maxFee, SameRange());

        _daoFeeRange.min = _minFee;
        _daoFeeRange.max = _maxFee;

        emit DaoFeeChanged(_minFee, _maxFee);
    }

    function _setMaxDeployerFee(uint256 _newMaxDeployerFee) internal virtual {
        require(_newMaxDeployerFee <= MAX_FEE, MaxFeeExceeded());

        maxDeployerFee = _newMaxDeployerFee;

        emit MaxDeployerFeeChanged(_newMaxDeployerFee);
    }

    function _setMaxFlashloanFee(uint256 _newMaxFlashloanFee) internal virtual {
        require(_newMaxFlashloanFee <= MAX_FEE, MaxFeeExceeded());

        maxFlashloanFee = _newMaxFlashloanFee;

        emit MaxFlashloanFeeChanged(_newMaxFlashloanFee);
    }

    function _setMaxLiquidationFee(uint256 _newMaxLiquidationFee) internal virtual {
        require(_newMaxLiquidationFee <= MAX_FEE, MaxFeeExceeded());

        maxLiquidationFee = _newMaxLiquidationFee;

        emit MaxLiquidationFeeChanged(_newMaxLiquidationFee);
    }

    function _setDaoFeeReceiver(address _newDaoFeeReceiver) internal virtual {
        require(_newDaoFeeReceiver != address(0), DaoFeeReceiverZeroAddress());

        daoFeeReceiver = _newDaoFeeReceiver;

        emit DaoFeeReceiverChanged(_newDaoFeeReceiver);
    }

    function _setDaoFeeReceiver(
        mapping(address => address) storage _mapping,
        address _mappingKey,
        address _newDaoFeeReceiver
    ) internal virtual {
        address currentValue = _mapping[_mappingKey];
        require((uint160(currentValue) | uint160(_newDaoFeeReceiver)) != 0, DaoFeeReceiverZeroAddress());
        require(currentValue != _newDaoFeeReceiver, SameDaoFeeReceiver());

        _mapping[_mappingKey] = _newDaoFeeReceiver;
    }

    function _cloneShareTokensAndValidate(
        ISiloConfig _siloConfig,
        ISilo _silo0,
        ISilo _silo1,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl,
        uint256 _creatorSiloCounter,
        address _creator
    ) internal virtual {
        address createdProtectedShareToken0 = CloneDeterministic.shareProtectedCollateralToken0(
            _shareProtectedCollateralTokenImpl, _creatorSiloCounter, _creator
        );

        address createdProtectedShareToken1 = CloneDeterministic.shareProtectedCollateralToken1(
            _shareProtectedCollateralTokenImpl, _creatorSiloCounter, _creator
        );

        address createdDebtShareToken0 = CloneDeterministic.shareDebtToken0(
            _shareDebtTokenImpl, _creatorSiloCounter, _creator
        );

        address createdDebtShareToken1 = CloneDeterministic.shareDebtToken1(
            _shareDebtTokenImpl, _creatorSiloCounter, _creator
        );

        _validateShareTokens(_siloConfig, address(_silo0), createdProtectedShareToken0, createdDebtShareToken0);
        _validateShareTokens(_siloConfig, address(_silo1), createdProtectedShareToken1, createdDebtShareToken1);
    }

    function _validateShareTokens(
        ISiloConfig _siloConfig,
        address _silo,
        address _createdProtectedShareToken,
        address _createdDebtShareToken
    ) internal virtual {
        (
            address protectedShareToken,
            address collateralShareToken,
            address debtShareToken
        ) = _siloConfig.getShareTokens(_silo);

        require(_silo == collateralShareToken, ConfigMismatchShareCollateralToken());
        require(protectedShareToken == _createdProtectedShareToken, ConfigMismatchShareProtectedToken());
        require(debtShareToken == _createdDebtShareToken, ConfigMismatchShareDebtToken());
    }

    function _initializeShareTokens(ISiloConfig _siloConfig, ISilo _silo0, ISilo _silo1) internal virtual {
        uint24 protectedTokenType = uint24(Hook.PROTECTED_TOKEN);
        uint24 debtTokenType = uint24(Hook.DEBT_TOKEN);

        // initialize silo0 share tokens
        address hookReceiver0 = IShareToken(address(_silo0)).hookReceiver();
        (address protectedShareToken0, , address debtShareToken0) = _siloConfig.getShareTokens(address(_silo0));

        IShareTokenInitializable(protectedShareToken0).initialize(_silo0, hookReceiver0, protectedTokenType);
        IShareTokenInitializable(debtShareToken0).initialize(_silo0, hookReceiver0, debtTokenType);

        // initialize silo1 share tokens
        address hookReceiver1 = IShareToken(address(_silo1)).hookReceiver();
        (address protectedShareToken1, , address debtShareToken1) = _siloConfig.getShareTokens(address(_silo1));

        IShareTokenInitializable(protectedShareToken1).initialize(_silo1, hookReceiver1, protectedTokenType);
        IShareTokenInitializable(debtShareToken1).initialize(_silo1, hookReceiver1, debtTokenType);
    }
}
