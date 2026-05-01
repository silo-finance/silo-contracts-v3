// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloIncentivesController} from "../interfaces/ISiloIncentivesController.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {IDistributionManager} from "../interfaces/IDistributionManager.sol";
import {DistributionManager} from "../base/DistributionManager.sol";
import {SiloIncentivesController} from "../SiloIncentivesController.sol";

import {SiloIncentivesControllerCompatible} from "../SiloIncentivesControllerCompatible.sol";
import {
    IPermissionedLiquidationIncentiveController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationIncentiveController.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

/// @dev Fully functional SiloIncentivesControllerCompatible contract, with features that allow to disable liquidations
/// This contract should be set as a gauge for collateral or protected share tokens.
/// Disabling liquidation will not work, if it will be set for the shared debt token.
contract PermissionedLiquidationIncentiveController is
    IPermissionedLiquidationIncentiveController,
    SiloIncentivesControllerCompatible,
    Whitelist
{
    address public hookReceiver;

    address public anySilo;

    /// @inheritdoc IPermissionedLiquidationIncentiveController
    bool public enabled;

    bool private transient _liquidationAllowed;

    modifier onlyHookReceiver() {
        require(msg.sender == hookReceiver, OnlyHookReceiver());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @param _shareTokenAddress collateral or protected share token address
    /// @param _liquidationEnabled if true, the permissioned liquidation feature will be enabled
    function initialize(IShareToken _shareTokenAddress, bool _liquidationEnabled) external initializer {
        address hook = _shareTokenAddress.hookReceiver();

        anySilo = address(_shareTokenAddress.silo());
        hookReceiver = hook;

        __DistributionManager_init(hook);
        __SiloIncentivesController_init(address(_shareTokenAddress));
        __Whitelist_init(Ownable(hook).owner());

        _setEnabled(_liquidationEnabled);
    }

    /// @inheritdoc IPermissionedLiquidationIncentiveController
    function setEnabled(bool _enabled) external virtual onlyOwner {
        require(enabled != _enabled, EnabledAlreadySet());

        _setEnabled(_enabled);
    }

    /// @inheritdoc IPermissionedLiquidationIncentiveController
    function allowMeToLiquidate() external virtual onlyAllowed {
        _liquidationAllowed = true;
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override(SiloIncentivesController, IVersioned) returns (string memory) {
        return "PermissionedLiquidationIncentiveController 4.12.0";
    }

    function afterTokenTransfer(
        address _sender,
        uint256 _senderBalance,
        address _recipient,
        uint256 _recipientBalance,
        uint256 _totalSupply,
        uint256 _amount
    )
        public
        virtual
        override(SiloIncentivesControllerCompatible, ISiloIncentivesController)
        onlyHookReceiver
    {
        if (enabled && !_liquidationAllowed) {
            // is this liquidation?
            // After transferring collateral, the user will always be insolvent in case of liquidation
            require(ISilo(anySilo).isSolvent(_sender), LiquidationNotAllowed());
        }

        super.afterTokenTransfer({
            _sender: _sender,
            _senderBalance: _senderBalance,
            _recipient: _recipient,
            _recipientBalance: _recipientBalance,
            _totalSupply: _totalSupply,
            _amount: _amount
        });
    }

    // solhint-disable-next-line func-name-mixedcase
    function NOTIFIER() public view override(DistributionManager, IDistributionManager) returns (address) {
        return hookReceiver;
    }

    function _setEnabled(bool _enabled) internal virtual {
        if (_enabled) {
            address shareTokenAddress = address(_shareToken());

            ISiloConfig siloConfig = IShareToken(shareTokenAddress).siloConfig();
            address silo = address(IShareToken(shareTokenAddress).silo());

            ISiloConfig.ConfigData memory cfg = siloConfig.getConfig(silo);
            require(cfg.lt != 0, NotCollateralSilo());

            require(
                cfg.collateralShareToken == shareTokenAddress
                    || cfg.protectedShareToken == shareTokenAddress,
                NotCollateralShareToken()
            );
        }

        enabled = _enabled;
        emit EnabledChanged(_enabled);
    }
}
