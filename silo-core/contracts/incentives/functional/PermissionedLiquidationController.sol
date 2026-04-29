// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5/proxy/utils/Initializable.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {BaseIncentivesControllerCompatible} from "../base/BaseIncentivesControllerCompatible.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";
import {Versioned} from "silo-core/contracts/interfaces/Versioned.sol";

/// @dev this contract should be set as a gauge for collateral or protected share tokens.
/// It will not work if it will be set for the shared debt token.
contract PermissionedLiquidationController is
    IPermissionedLiquidationController,
    BaseIncentivesControllerCompatible,
    Whitelist,
    Initializable,
    Versioned
{
    address public hookReceiver;

    address public anySilo;

    bool public enabled = true;

    bool private transient _liquidationAllowed;

    modifier onlyHookReceiver() {
        require(msg.sender == hookReceiver, OnlyHookReceiver());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @param _notifier hook address
    function initialize(address _notifier) external initializable {
        hookReceiver = _notifier;
        __Whitelist_init(Ownable(_notifier).owner());

        (anySilo,) = BaseHookReceiver(_notifier).siloConfig().getSilos();
    }

    /// @inheritdoc IPermissionedLiquidationController
    function setEnabled(bool _enabled) external onlyOwner {
        enabled = _enabled;
    }

    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "PermissionedLiquidationController 4.10.0";
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
        bool isLiquidation = !ISilo(anySilo).isSolvent(_sender);

        if (isLiquidation) revert LiquidationNotAllowed();
    }

    /// @inheritdoc IPermissionedLiquidationController
    function allowMeToLiquidate() external virtual onlyAllowed {
        _liquidationAllowed = true;
    }

    function _onlyOwner() internal view virtual override {
        require(msg.sender == Ownable(hookReceiver).owner(), OnlyOwner());
    }
}
