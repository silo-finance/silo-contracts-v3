// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ShareTokenLib} from "../lib/ShareTokenLib.sol";
import {ShareCollateralTokenLib} from "../lib/ShareCollateralTokenLib.sol";
import {IShareToken, ShareToken} from "./ShareToken.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";

/// @title ShareCollateralToken
/// @notice ERC20 compatible token representing collateral in Silo
/// @custom:security-contact security@silo.finance
abstract contract ShareCollateralToken is ShareToken {
    /// @inheritdoc IShareToken
    function mint(address _owner, address /* _spender */, uint256 _amount) external virtual override onlySilo {
        _mint(_owner, _amount);
    }

    /// @inheritdoc IShareToken
    function burn(address _owner, address _spender, uint256 _amount) external virtual override onlySilo {
        if (_owner != _spender) _spendAllowance(_owner, _spender, _amount);
        _burn(_owner, _amount);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "ShareCollateralToken 4.0.0";
    }

    /// @dev Check if sender is solvent after the transfer
    function _afterTokenTransfer(address _sender, address _recipient, uint256 _amount) internal virtual override {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();

        // for minting or burning, Silo is responsible to check all necessary conditions
        // for transfer make sure that _sender is solvent after transfer
        if (ShareTokenLib.isTransfer(_sender, _recipient) && $.transferWithChecks) {
            bool senderIsSolvent = ShareCollateralTokenLib.isSolventAfterCollateralTransfer(_sender);
            require(senderIsSolvent, IShareToken.SenderNotSolventAfterTransfer());
        }

        ShareToken._afterTokenTransfer(_sender, _recipient, _amount);
    }
}
