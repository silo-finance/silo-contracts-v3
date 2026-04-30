// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";

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
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

/// @dev this contract should be set as a gauge for collateral or protected share tokens.
/// It will not work if it will be set for the shared debt token.
contract PermissionedLiquidationController is
    IPermissionedLiquidationController,
    SiloIncentivesControllerCompatible,
    Whitelist,
    Initializable
{
    address public hookReceiver;

    address public anySilo;

    address public collateralShareToken;

    bool public enabled;

    bool private transient _liquidationAllowed;

    modifier onlyHookReceiver() {
        require(msg.sender == hookReceiver, OnlyHookReceiver());
        _;
    }

    constructor() SiloIncentivesControllerCompatible(address(0xdead), address(0xdead), address(0xdead)) {
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
        anySilo = collateralSilo;
        collateralShareToken = address(_collateralShareToken);
        enabled = true;

        __Whitelist_init(Ownable(hook).owner());
    }

    /// @inheritdoc IPermissionedLiquidationController
    function setEnabled(bool _enabled) external virtual onlyOwner {
        require(enabled != _enabled, EnabledAlreadySet());

        enabled = _enabled;
        emit EnabledChanged(_enabled);
    }

    /// @inheritdoc IPermissionedLiquidationController
    function allowMeToLiquidate() external virtual onlyAllowed {
        _liquidationAllowed = true;
    }

    // solhint-disable-next-line func-name-mixedcase
    function share_token() external view virtual override returns (address) {
        return collateralShareToken;
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override(SiloIncentivesController, IVersioned) returns (string memory) {
        return "PermissionedLiquidationController 4.12.0";
    }

    function afterTokenTransfer(
        address _sender,
        uint256,
        /*_senderBalance*/
        address,
        /*_recipient*/
        uint256,
        /*_recipientBalance*/
        uint256,
        /*_totalSupply*/
        uint256 /*_amount*/
    )
        public
        virtual
        override(SiloIncentivesControllerCompatible, ISiloIncentivesController)
        onlyHookReceiver
    {
        if (!enabled) return;
        if (_liquidationAllowed) return;

        // is this liquidation?
        // After transferring collateral, the user will always be insolvent.
        bool isLiquidation = !ISilo(anySilo).isSolvent(_sender);

        if (isLiquidation) revert LiquidationNotAllowed();
    }

    // solhint-disable-next-line func-name-mixedcase
    function SHARE_TOKEN()
        public
        view
        override(SiloIncentivesController, ISiloIncentivesController)
        returns (address)
    {
        return collateralShareToken;
    }

    // solhint-disable-next-line func-name-mixedcase
    function NOTIFIER() public view override(DistributionManager, IDistributionManager) returns (address) {
        return hookReceiver;
    }
}
