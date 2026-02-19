// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/// @dev Hook receiver for all actions with events to see decoded inputs
/// This contract is designed to be deployed for each test case
contract HookReceiverAllActionsWithEvents is PartialLiquidation {
    using Hook for uint256;

    bool internal constant _IS_BEFORE = true;
    bool internal constant _IS_AFTER = false;
    bool internal constant _SAME_ASSET = true;
    bool internal constant _NOT_SAME_ASSET = false;

    uint24 internal immutable _SILO0_ACTIONS_BEFORE;
    uint24 internal immutable _SILO0_ACTIONS_AFTER;
    uint24 internal immutable _SILO1_ACTIONS_BEFORE;
    uint24 internal immutable _SILO1_ACTIONS_AFTER;

    bool public revertAllActions;
    bool public revertOnlyBeforeAction;
    bool public revertOnlyAfterAction;

    // Events to be emitted by the hook receiver to see decoded inputs
    // HA - Hook Action
    event DepositBeforeHA(
        address silo, uint256 assets, uint256 shares, address receiver, ISilo.CollateralType collateralType
    );

    event DepositAfterHA( // The exact amount of assets being deposited
        // The exact amount of shares being minted
        address silo,
        uint256 depositedAssets,
        uint256 depositedShares,
        uint256 receivedAssets,
        uint256 mintedShares,
        address receiver,
        ISilo.CollateralType collateralType
    );

    event ShareTokenAfterHA(
        address silo,
        address sender,
        address recipient,
        uint256 amount,
        uint256 senderBalance,
        uint256 recipientBalance,
        uint256 totalSupply,
        ISilo.CollateralType collateralType
    );

    event DebtShareTokenAfterHA(
        address silo,
        address sender,
        address recipient,
        uint256 amount,
        uint256 senderBalance,
        uint256 recipientBalance,
        uint256 totalSupply
    );

    event WithdrawBeforeHA(
        address silo,
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        address spender,
        ISilo.CollateralType collateralType
    );

    event WithdrawAfterHA(
        address silo,
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        address spender,
        uint256 withdrawnAssets,
        uint256 withdrawnShares,
        ISilo.CollateralType collateralType
    );

    event BorrowBeforeHA(
        address silo,
        uint256 borrowedAssets,
        uint256 borrowedShares,
        address borrower,
        address receiver,
        address spender
    );

    event BorrowAfterHA(
        address silo,
        uint256 borrowedAssets,
        uint256 borrowedShares,
        address borrower,
        address receiver,
        address spender,
        uint256 returnedAssets,
        uint256 returnedShares
    );

    event RepayBeforeHA(
        address silo, uint256 repaidAssets, uint256 repaidShares, address borrower, address repayer
    );

    event RepayAfterHA(
        address silo,
        uint256 repaidAssets,
        uint256 repaidShares,
        address borrower,
        address repayer,
        uint256 returnedAssets,
        uint256 returnedShares
    );

    event TransitionCollateralHA(address silo, uint256 shares, address owner, uint256 assets, bool isBefore);

    event FlashLoanBeforeHA(address silo, address receiver, address token, uint256 amount);

    event FlashLoanAfterHA(address silo, address receiver, address token, uint256 amount, uint256 fee);

    error ActionsStopped();
    error ShareTokenBeforeForbidden();
    error UnknownAction();
    error UnknownBorrowAction();
    error UnknownShareTokenAction();
    error UnknownSwitchCollateralAction();

    // designed to be deployed for each test case
    constructor(
        uint256 _silo0ActionsBefore,
        uint256 _silo0ActionsAfter,
        uint256 _silo1ActionsBefore,
        uint256 _silo1ActionsAfter
    ) {
        _SILO0_ACTIONS_BEFORE = SafeCast.toUint24(_silo0ActionsBefore);
        _SILO0_ACTIONS_AFTER = SafeCast.toUint24(_silo0ActionsAfter);
        _SILO1_ACTIONS_BEFORE = SafeCast.toUint24(_silo1ActionsBefore);
        _SILO1_ACTIONS_AFTER = SafeCast.toUint24(_silo1ActionsAfter);
    }

    /// @inheritdoc IHookReceiver
    function initialize(ISiloConfig _config, bytes calldata) public override {
        siloConfig = _config;

        (address silo0, address silo1) = siloConfig.getSilos();

        // Set hooks for all actions for both silos
        _setHookConfig(silo0, _SILO0_ACTIONS_BEFORE, _SILO0_ACTIONS_AFTER);
        _setHookConfig(silo1, _SILO1_ACTIONS_BEFORE, _SILO1_ACTIONS_AFTER);
    }

    function revertAnyAction() external {
        revertAllActions = true;
    }

    function revertBeforeAction() external {
        revertOnlyBeforeAction = true;
    }

    function revertAfterAction() external {
        revertOnlyAfterAction = true;
    }

    /// @inheritdoc IHookReceiver
    function beforeAction(address _silo, uint256 _action, bytes calldata _inputAndOutput) external {
        if (revertAllActions || revertOnlyBeforeAction) revert ActionsStopped();
        _processActions(_silo, _action, _inputAndOutput, _IS_BEFORE);
    }

    /// @inheritdoc IHookReceiver
    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput) external override {
        if (revertAllActions || revertOnlyAfterAction) revert ActionsStopped();
        _processActions(_silo, _action, _inputAndOutput, _IS_AFTER);
    }

    function _processActions(address _silo, uint256 _action, bytes calldata _inputAndOutput, bool _isBefore)
        internal
    {
        if (_action.matchAction(Hook.DEPOSIT)) {
            _processDeposit(_silo, _action, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.SHARE_TOKEN_TRANSFER)) {
            _processShareTokenTransfer(_silo, _action, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.WITHDRAW)) {
            _processWithdraw(_silo, _action, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.BORROW)) {
            _processBorrow(_silo, _action, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.BORROW_SAME_ASSET)) {
            _processBorrow(_silo, _action, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.REPAY)) {
            _processRepay(_silo, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.FLASH_LOAN)) {
            _processFlashLoan(_silo, _inputAndOutput, _isBefore);
        } else if (_action.matchAction(Hook.TRANSITION_COLLATERAL)) {
            _processTransitionCollateral(_silo, _inputAndOutput, _isBefore);
        } else {
            revert UnknownAction();
        }
    }

    function _processDeposit(address _silo, uint256 _action, bytes calldata _inputAndOutput, bool _isBefore)
        internal
    {
        bool isCollateral = _action.matchAction(Hook.depositAction(ISilo.CollateralType.Collateral));

        ISilo.CollateralType collateralType =
            isCollateral ? ISilo.CollateralType.Collateral : ISilo.CollateralType.Protected;

        if (_isBefore) {
            Hook.BeforeDepositInput memory input = Hook.beforeDepositDecode(_inputAndOutput);
            emit DepositBeforeHA(_silo, input.assets, input.shares, input.receiver, collateralType);
        } else {
            Hook.AfterDepositInput memory input = Hook.afterDepositDecode(_inputAndOutput);

            emit DepositAfterHA(
                _silo,
                input.assets,
                input.shares,
                input.receivedAssets,
                input.mintedShares,
                input.receiver,
                collateralType
            );
        }
    }

    function _processShareTokenTransfer(
        address _silo,
        uint256 _action,
        bytes calldata _inputAndOutput,
        bool _isBefore
    ) internal {
        if (_isBefore) revert ShareTokenBeforeForbidden();

        Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_inputAndOutput);

        if (_action.matchAction(Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN))) {
            emit ShareTokenAfterHA(
                _silo,
                input.sender,
                input.recipient,
                input.amount,
                input.senderBalance,
                input.recipientBalance,
                input.totalSupply,
                ISilo.CollateralType.Collateral
            );
        } else if (_action.matchAction(Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN))) {
            emit ShareTokenAfterHA(
                _silo,
                input.sender,
                input.recipient,
                input.amount,
                input.senderBalance,
                input.recipientBalance,
                input.totalSupply,
                ISilo.CollateralType.Protected
            );
        } else if (_action.matchAction(Hook.shareTokenTransfer(Hook.DEBT_TOKEN))) {
            emit DebtShareTokenAfterHA(
                _silo,
                input.sender,
                input.recipient,
                input.amount,
                input.senderBalance,
                input.recipientBalance,
                input.totalSupply
            );
        } else {
            revert UnknownShareTokenAction();
        }
    }

    function _processWithdraw(address _silo, uint256 _action, bytes calldata _inputAndOutput, bool _isBefore)
        internal
    {
        bool isCollateral = _action.matchAction(Hook.withdrawAction(ISilo.CollateralType.Collateral));

        ISilo.CollateralType collateralType =
            isCollateral ? ISilo.CollateralType.Collateral : ISilo.CollateralType.Protected;

        if (_isBefore) {
            Hook.BeforeWithdrawInput memory input = Hook.beforeWithdrawDecode(_inputAndOutput);

            emit WithdrawBeforeHA(
                _silo, input.assets, input.shares, input.receiver, input.owner, input.spender, collateralType
            );
        } else {
            Hook.AfterWithdrawInput memory input = Hook.afterWithdrawDecode(_inputAndOutput);

            emit WithdrawAfterHA(
                _silo,
                input.assets,
                input.shares,
                input.receiver,
                input.owner,
                input.spender,
                input.withdrawnAssets,
                input.withdrawnShares,
                collateralType
            );
        }
    }

    function _processBorrow(address _silo, uint256 _action, bytes calldata _inputAndOutput, bool _isBefore)
        internal
    {
        if (_action.matchAction(Hook.BORROW)) {
            _processBorrowAction(_silo, _inputAndOutput, _isBefore);
        } else {
            revert UnknownBorrowAction();
        }
    }

    function _processBorrowAction(address _silo, bytes calldata _inputAndOutput, bool _isBefore) internal {
        if (_isBefore) {
            Hook.BeforeBorrowInput memory input = Hook.beforeBorrowDecode(_inputAndOutput);

            emit BorrowBeforeHA(_silo, input.assets, input.shares, input.borrower, input.receiver, input.spender);
        } else {
            Hook.AfterBorrowInput memory input = Hook.afterBorrowDecode(_inputAndOutput);

            emit BorrowAfterHA(
                _silo,
                input.assets,
                input.shares,
                input.borrower,
                input.receiver,
                input.spender,
                input.borrowedAssets,
                input.borrowedShares
            );
        }
    }

    function _processRepay(address _silo, bytes calldata _inputAndOutput, bool _isBefore) internal {
        if (_isBefore) {
            Hook.BeforeRepayInput memory input = Hook.beforeRepayDecode(_inputAndOutput);
            emit RepayBeforeHA(_silo, input.assets, input.shares, input.borrower, input.repayer);
        } else {
            Hook.AfterRepayInput memory input = Hook.afterRepayDecode(_inputAndOutput);

            emit RepayAfterHA(
                _silo,
                input.assets,
                input.shares,
                input.borrower,
                input.repayer,
                input.repaidAssets,
                input.repaidShares
            );
        }
    }

    function _processFlashLoan(address _silo, bytes calldata _inputAndOutput, bool _isBefore) internal {
        if (_isBefore) {
            Hook.BeforeFlashLoanInput memory input = Hook.beforeFlashLoanDecode(_inputAndOutput);
            emit FlashLoanBeforeHA(_silo, input.receiver, input.token, input.amount);
        } else {
            Hook.AfterFlashLoanInput memory input = Hook.afterFlashLoanDecode(_inputAndOutput);
            emit FlashLoanAfterHA(_silo, input.receiver, input.token, input.amount, input.fee);
        }
    }

    function _processTransitionCollateral(address _silo, bytes calldata _inputAndOutput, bool _isBefore) internal {
        if (_isBefore) {
            Hook.BeforeTransitionCollateralInput memory input =
                Hook.beforeTransitionCollateralDecode(_inputAndOutput);
            emit TransitionCollateralHA(_silo, input.shares, input.owner, 0, _isBefore);
        } else {
            Hook.AfterTransitionCollateralInput memory input = Hook.afterTransitionCollateralDecode(_inputAndOutput);
            emit TransitionCollateralHA(_silo, input.shares, input.owner, input.assets, _isBefore);
        }
    }
}
