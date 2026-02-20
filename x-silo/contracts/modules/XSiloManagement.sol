// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";

import {INotificationReceiver} from "silo-vaults/contracts/interfaces/INotificationReceiver.sol";

import {IXSiloManagement} from "../interfaces/IXSiloManagement.sol";
import {IStream} from "../interfaces/IStream.sol";

abstract contract XSiloManagement is IXSiloManagement, Ownable2Step {
    IStream public stream;

    INotificationReceiver public notificationReceiver;

    constructor(address _initialOwner, address _stream) Ownable(_initialOwner) {
        // it is optional and can be address(0)
        // we have to skip check because of deployment scripts: they using precalculated addresses
        if (_stream != address(0)) _setStream({_stream: IStream(_stream), _skipBeneficiaryCheck: true});
    }

    /// @inheritdoc IXSiloManagement
    function setNotificationReceiver(INotificationReceiver _notificationReceiver, bool _allProgramsStopped)
        external
        onlyOwner
    {
        require(notificationReceiver != _notificationReceiver, NoChange());
        require(_allProgramsStopped, StopAllRelatedPrograms());

        notificationReceiver = _notificationReceiver;
        emit NotificationReceiverUpdate(_notificationReceiver);
    }

    /// @inheritdoc IXSiloManagement
    function setStream(IStream _stream) external onlyOwner {
        _setStream(_stream, false);
    }

    function _setStream(IStream _stream, bool _skipBeneficiaryCheck) internal {
        require(stream != _stream, NoChange());
        require(_skipBeneficiaryCheck || _stream.BENEFICIARY() == address(this), NotBeneficiary());

        stream = _stream;
        emit StreamUpdate(_stream);
    }
}
