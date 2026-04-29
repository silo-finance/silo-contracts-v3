// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SiloIncentivesControllerCompatible} from "../SiloIncentivesControllerCompatible.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";

contract PermissionedLiquidationController is
    IPermissionedLiquidationController,
    SiloIncentivesControllerCompatible,
    Whitelist
{
    address public immutable HOOK_RECEIVER;

    bool public enabled = true;

    bool private transient _liquidationAllowed;

    modifier onlyHookReceiver() {
        require(msg.sender == HOOK_RECEIVER, OnlyHookReceiver());
        _;
    }

    /// @param _owner owner of the contract
    /// @param _notifier for Silo it should be hook address
    /// @param _shareTokenAddress protected or collateral share token address
    constructor(address _owner, address _notifier, address _shareTokenAddress)
        SiloIncentivesControllerCompatible(_owner, _notifier, _shareTokenAddress)
    {
        __Whitelist_init(_owner);

        HOOK_RECEIVER = IShareToken(_shareTokenAddress).hookReceiver();
        require(address(HOOK_RECEIVER) == _notifier, InvalidHookReceiver());

        address collateralSilo = address(IShareToken(_shareTokenAddress).silo());
        ISiloConfig siloConfig = IShareToken(_shareTokenAddress).siloConfig();

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(collateralSilo);
        require(collateralConfig.lt != 0, NotCollateralSilo());

        require(
            collateralConfig.collateralShareToken == _shareTokenAddress
                || collateralConfig.protectedShareToken == _shareTokenAddress,
            NotCollateralShareToken()
        );
    }

    /// @inheritdoc IPermissionedLiquidationController
    function setEnabled(bool _enabled) external onlyOwner {
        enabled = _enabled;
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
        override
        onlyHookReceiver
    {
        if (!enabled) return;
        if (_liquidationAllowed) return;

        // is this liquidation?
        // After transferring collateral, the user will always be insolvent.
        (address anySilo,) = BaseHookReceiver(msg.sender).siloConfig().getSilos();
        bool isLiquidation = !ISilo(anySilo).isSolvent(_sender);

        if (isLiquidation) revert LiquidationNotAllowed();
    }

    /// @inheritdoc IPermissionedLiquidationController
    function allowMeToLiquidate() external virtual onlyAllowed {
        _liquidationAllowed = true;
    }
}
