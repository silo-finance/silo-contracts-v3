// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20R} from "../interfaces/IERC20R.sol";
import {IShareToken, ShareToken, ISilo} from "./ShareToken.sol";
import {NonReentrantLib} from "../lib/NonReentrantLib.sol";
import {ShareTokenLib} from "../lib/ShareTokenLib.sol";
import {ERC20RStorageLib} from "../lib/ERC20RStorageLib.sol";
import {IShareTokenInitializable} from "../interfaces/IShareTokenInitializable.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";

/// @title ShareDebtToken
/// @notice ERC20 compatible token representing debt in Silo
/// @dev It implements reversed approvals and checks solvency of recipient on transfer.
///
/// It is assumed that there is no attack vector on taking someone else's debt because we don't see
/// economical reason why one would do such thing. For that reason anyone can transfer owner's token
/// to any recipient as long as receiving wallet approves the transfer. In other words, anyone can
/// take someone else's debt without asking.
/// @custom:security-contact security@silo.finance
contract ShareDebtToken is IERC20R, ShareToken, IShareTokenInitializable {
    /// @inheritdoc IShareTokenInitializable
    function callOnBehalfOfShareToken(address _target, uint256 _value, ISilo.CallType _callType, bytes calldata _input)
        external
        payable
        virtual
        onlyHookReceiver()
        returns (bool success, bytes memory result)
    {
        (success, result) = ShareTokenLib.callOnBehalfOfShareToken(_target, _value, _callType, _input);
    }

    /// @inheritdoc IShareTokenInitializable
    function initialize(ISilo _silo, address _hookReceiver, uint24 _tokenType) external virtual {
        _shareTokenInitialize(_silo, _hookReceiver, _tokenType);
    }

    /// @inheritdoc IShareToken
    function mint(address _owner, address _spender, uint256 _amount) external virtual override onlySilo {
        // For `_spendReceiveApproval`, `_spender` is the owner of the debt token
        // which is the `msg.sender` when borrowing and `_owner` is the recipient of the debt
        // because debt share token is minted to `_owner`
        if (_owner != _spender) _spendReceiveApproval(_spender, _owner, _amount);
        _mint(_owner, _amount);
    }

    /// @inheritdoc IShareToken
    function burn(address _owner, address /* _spender */, uint256 _amount) external virtual override onlySilo {
        _burn(_owner, _amount);
    }

    /// @inheritdoc IERC20R
    function setReceiveApproval(address owner, uint256 _amount) external virtual override {
        NonReentrantLib.nonReentrant(ShareTokenLib.getShareTokenStorage().siloConfig);

        _setReceiveApproval(owner, _msgSender(), _amount);
    }

    /// @inheritdoc IShareToken
    function decimalsOffset() external view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "ShareDebtToken 4.0.0";
    }

    /// @inheritdoc IERC20R
    function decreaseReceiveAllowance(address _owner, uint256 _subtractedValue) public virtual override {
        NonReentrantLib.nonReentrant(ShareTokenLib.getShareTokenStorage().siloConfig);

        uint256 currentAllowance = _receiveAllowance(_owner, _msgSender());

        uint256 newAllowance;

        unchecked {
            // We will not underflow because of the condition `currentAllowance < _subtractedValue`
            newAllowance = currentAllowance < _subtractedValue ? 0 : currentAllowance - _subtractedValue;
        }

        _setReceiveApproval(_owner, _msgSender(), newAllowance);
    }

    /// @inheritdoc IERC20R
    function increaseReceiveAllowance(address _owner, uint256 _addedValue) public virtual override {
        NonReentrantLib.nonReentrant(ShareTokenLib.getShareTokenStorage().siloConfig);

        uint256 currentAllowance = _receiveAllowance(_owner, _msgSender());

        _setReceiveApproval(_owner, _msgSender(), currentAllowance + _addedValue);
    }

    /// @inheritdoc IERC20R
    function receiveAllowance(address _owner, address _recipient) public view virtual override returns (uint256) {
        return _receiveAllowance(_owner, _recipient);
    }

    /// @dev Set approval for `_owner` to send debt to `_recipient`
    /// @param _owner owner of debt token
    /// @param _recipient wallet that allows `_owner` to send debt to its wallet
    /// @param _amount amount of token allowed to be transferred
    function _setReceiveApproval(address _owner, address _recipient, uint256 _amount) internal virtual {
        require(_owner != address(0), IShareToken.OwnerIsZero());
        require(_recipient != address(0), IShareToken.RecipientIsZero());

        IERC20R.Storage storage $ = ERC20RStorageLib.getIERC20RStorage();

        $._receiveAllowances[_owner][_recipient] = _amount;

        emit ReceiveApproval(_owner, _recipient, _amount);
    }

    /// @dev Check receive allowance and if recipient is allowed to accept debt from silo
    function _beforeTokenTransfer(address _sender, address _recipient, uint256 _amount)
        internal
        virtual
        override
    {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();

        // If we are minting or burning, Silo is responsible to check all necessary conditions
        if (ShareTokenLib.isTransfer(_sender, _recipient)) {
            // Silo forbids having two debts and this condition will be checked inside `onDebtTransfer`.
            // If the `_recipient` has no collateral silo set yet, it will be copied from the sender.
            $.siloConfig.onDebtTransfer(_sender, _recipient);

            // if we NOT doing checks, we early return and not checking/changing any allowance
            if (!$.transferWithChecks) return;

            _spendReceiveApproval(_sender, _recipient, _amount);
        }
    }

    /// @dev Check if recipient is solvent after debt transfer
    function _afterTokenTransfer(address _sender, address _recipient, uint256 _amount) internal virtual override {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();

        // if we are minting or burning, Silo is responsible to check all necessary conditions
        // if we are NOT minting and not burning, it means we are transferring
        // make sure that _recipient is solvent after transfer
        if (ShareTokenLib.isTransfer(_sender, _recipient) && $.transferWithChecks) {
            $.siloConfig.accrueInterestForBothSilos();
            ShareTokenLib.callOracleBeforeQuote($.siloConfig, _recipient);
            require($.silo.isSolvent(_recipient), IShareToken.RecipientNotSolventAfterTransfer());
        }

        ShareToken._afterTokenTransfer(_sender, _recipient, _amount);
    }

    function _spendReceiveApproval(address _sender, address _recipient, uint256 _amount) internal virtual {
        // _recipient must approve debt transfer, _sender does not have to
        uint256 currentAllowance = _receiveAllowance(_sender, _recipient);
        require(currentAllowance >= _amount, IShareToken.AmountExceedsAllowance());

        uint256 newDebtAllowance;

        // There can't be an underflow in the subtraction because of the previous check
        unchecked {
            // update debt allowance
            newDebtAllowance = currentAllowance - _amount;
        }

        _setReceiveApproval(_sender, _recipient, newDebtAllowance);
    }

    function _receiveAllowance(address _owner, address _recipient) internal view virtual returns (uint256) {
        return ERC20RStorageLib.getIERC20RStorage()._receiveAllowances[_owner][_recipient];
    }
}
