// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloIncentivesController} from "../interfaces/ISiloIncentivesController.sol";

import {BaseIncentivesControllerCompatible} from "../base/BaseIncentivesControllerCompatible.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

/// @dev this contract should be set as a gauge for collateral or protected share tokens.
/// It will not work if it will be set for the shared debt token.
/// When you set it for hook with defaulting liquidation, it's recommended to keep enable to false 
/// and use defaulting whitelist rather than permission and liquidation controller.
contract PermissionedLiquidationController is
    IPermissionedLiquidationController,
    BaseIncentivesControllerCompatible,
    Whitelist,
    Initializable
{
    address public hookReceiver;

    address public collateralShareToken;

    PermisionedData internal _permisionedData;

    bool private transient _liquidationAllowed;

    modifier onlyHookReceiver() {
        require(msg.sender == hookReceiver, OnlyHookReceiver());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @param _collateralShareToken collateral or protected share token address
    function initialize(IShareToken _collateralShareToken) external initializer {
        address hook = _collateralShareToken.hookReceiver();
        ISiloConfig siloConfig = _collateralShareToken.siloConfig();
        address collateralSilo = address(_collateralShareToken.silo());

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(collateralSilo);
        require(collateralConfig.lt != 0, NotCollateralSilo());

        require(
            collateralConfig.collateralShareToken == address(_collateralShareToken)
                || collateralConfig.protectedShareToken == address(_collateralShareToken),
            NotCollateralShareToken()
        );

        hookReceiver = hook;
        collateralShareToken = address(_collateralShareToken);
        _permisionedData = PermisionedData({anySilo: collateralSilo, enabled: false, pauseTokenTransfer: false});

        __Whitelist_init(Ownable(hookReceiver).owner());
    }

    /// @inheritdoc IPermissionedLiquidationController
    function setEnabled(bool _enabled) external onlyOwner {
        require(_permisionedData.enabled != _enabled, EnabledAlreadySet());

        _permisionedData.enabled = _enabled;
        emit EnabledChanged(_enabled);
    }

    /// @inheritdoc IPermissionedLiquidationController
    function setPause(bool _pauseTokenTransfer) external onlyOwner {
        require(_permisionedData.pauseTokenTransfer != _pauseTokenTransfer, PauseTokenTransferAlreadySet());

        _permisionedData.pauseTokenTransfer = _pauseTokenTransfer;
        if (_pauseTokenTransfer) {
            _permisionedData.enabled = true;
            emit EnabledChanged(true);
        }

        emit PauseTokenTransferChanged(_pauseTokenTransfer);
    }

    /// @inheritdoc IPermissionedLiquidationController
    function allowMeToLiquidate() external virtual onlyAllowed {
        _liquidationAllowed = true;
    }

    /// @inheritdoc IPermissionedLiquidationController
    function permisionedData() external view returns (PermisionedData memory data) {
        data = _permisionedData;
    }

    // solhint-disable-next-line func-name-mixedcase
    function share_token() external view virtual returns (address) {
        return collateralShareToken;
    }

    // solhint-disable-next-line func-name-mixedcase
    function SHARE_TOKEN() external view returns (address) {
        return collateralShareToken;
    }

    function NOTIFIER() external view returns (address) { // solhint-disable-line func-name-mixedcase
        return hookReceiver;
    }

    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "PermissionedLiquidationController 4.12.0";
    }

    function afterTokenTransfer(
        address _sender,
        uint256 /*_senderBalance*/,
        address /*_recipient*/,
        uint256 /*_recipientBalance*/,
        uint256 /*_totalSupply*/,
        uint256 /*_amount*/
    )
        public
        virtual
        override(BaseIncentivesControllerCompatible, ISiloIncentivesController)
        onlyHookReceiver
    {
        PermisionedData memory data = _permisionedData;

        if (!data.enabled) return;

        if (data.pauseTokenTransfer) revert PauseTokenTransferActive();

        if (_liquidationAllowed) return;

        // is this liquidation?
        // After transferring collateral, the user will always be insolvent.
        bool isLiquidation = !ISilo(data.anySilo).isSolvent(_sender);

        if (isLiquidation) revert LiquidationNotAllowed();
    }

    /// @dev to keep the interface backwards compatible, we need the owner method.
    function owner() public view virtual returns (address) {
        uint256 count = getRoleMemberCount(DEFAULT_ADMIN_ROLE);
        return count == 0 ? address(0) : getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

    function _onlyOwner() internal view virtual override {
        require(msg.sender == owner(), OnlyOwner());
    }
}
