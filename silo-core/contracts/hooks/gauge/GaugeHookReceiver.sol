// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// solhint-disable ordering

import {Ownable1and2Steps} from "common/access/Ownable1and2Steps.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver, IHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";

/// @notice Silo share token hook receiver for the gauge.
/// It notifies the gauge (if configured) about any balance update in the Silo share token.
abstract contract GaugeHookReceiver is BaseHookReceiver, IGaugeHookReceiver, Ownable1and2Steps {
    using Hook for uint256;
    using Hook for bytes;
    
    mapping(IShareToken => ISiloIncentivesController) public configuredGauges;

    constructor() Ownable1and2Steps(msg.sender) {
        // lock implementation
        _transferOwnership(address(0));
    }

    /// @inheritdoc IGaugeHookReceiver
    function setGauge(ISiloIncentivesController _gauge, IShareToken _shareToken) external virtual onlyOwner {
        require(address(_gauge) != address(0), EmptyGaugeAddress());
        require(_gauge.SHARE_TOKEN() == address(_shareToken), WrongGaugeShareToken());

        address configuredGauge = address(configuredGauges[_shareToken]);

        require(configuredGauge == address(0), GaugeAlreadyConfigured());

        address silo = address(_shareToken.silo());

        uint256 tokenType = _getTokenType(silo, address(_shareToken));
        uint256 hooksAfter = _getHooksAfter(silo);

        uint256 action = tokenType | Hook.SHARE_TOKEN_TRANSFER;
        hooksAfter = hooksAfter.addAction(action);

        _setHookConfig(silo, uint24(_getHooksBefore(silo)), uint24(hooksAfter));

        configuredGauges[_shareToken] = _gauge;

        emit GaugeConfigured(address(_gauge), address(_shareToken));
    }

    /// @inheritdoc IGaugeHookReceiver
    function removeGauge(IShareToken _shareToken) external virtual onlyOwner {
        ISiloIncentivesController configuredGauge = configuredGauges[_shareToken];

        require(address(configuredGauge) != address(0), GaugeIsNotConfigured());

        delete configuredGauges[_shareToken];

        emit GaugeRemoved(address(_shareToken));
    }

    /// @inheritdoc IHookReceiver
    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput)
        public
        virtual
        override
    {
        ISiloIncentivesController theGauge = configuredGauges[IShareToken(msg.sender)];

        if (theGauge == ISiloIncentivesController(address(0))) return;
        if (!_getHooksAfter(_silo).matchAction(_action)) return;

        Hook.AfterTokenTransfer memory input = _inputAndOutput.afterTokenTransferDecode();

        theGauge.afterTokenTransfer(
            input.sender,
            input.senderBalance,
            input.recipient,
            input.recipientBalance,
            input.totalSupply,
            input.amount
        );
    }

    /// @notice Get the token type for the share token
    /// @param _silo Silo address for which tokens was deployed
    /// @param _shareToken Share token address
    /// @dev Revert if wrong silo
    /// @dev Revert if the share token is not one of the collateral, protected or debt tokens
    function _getTokenType(address _silo, address _shareToken) internal view virtual returns (uint256) {
        (
            address protectedShareToken,
            address collateralShareToken,
            address debtShareToken
        ) = siloConfig.getShareTokens(_silo);

        if (_shareToken == collateralShareToken) return Hook.COLLATERAL_TOKEN;
        if (_shareToken == protectedShareToken) return Hook.PROTECTED_TOKEN;
        if (_shareToken == debtShareToken) return Hook.DEBT_TOKEN;

        revert InvalidShareToken();
    }

    /// @notice Set the owner of the hook receiver
    /// @param _owner Owner address
    function __GaugeHookReceiver_init(address _owner) // solhint-disable-line func-name-mixedcase
        internal
        onlyInitializing
        virtual
    {
        require(_owner != address(0), OwnerIsZeroAddress());

        _transferOwnership(_owner);
    }
}
