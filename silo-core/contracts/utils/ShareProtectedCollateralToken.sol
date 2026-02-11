// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ShareCollateralToken} from "./ShareCollateralToken.sol";
import {ShareTokenLib} from "../lib/ShareTokenLib.sol";
import {ISilo} from "../interfaces/ISilo.sol";
import {IShareTokenInitializable} from "../interfaces/IShareTokenInitializable.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";

contract ShareProtectedCollateralToken is ShareCollateralToken, IShareTokenInitializable {
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

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory) {
        return "ShareProtectedCollateralToken 4.0.0";
    }
}
