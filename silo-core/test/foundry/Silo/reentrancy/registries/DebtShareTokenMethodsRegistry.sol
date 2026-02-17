// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ShareTokenMethodsRegistry} from "./ShareTokenMethodsRegistry.sol";

import {TransferReentrancyTest} from "../methods/debt-share-token/TransferReentrancyTest.sol";
import {TransferFromReentrancyTest} from "../methods/debt-share-token/TransferFromReentrancyTest.sol";
import {SetReceiverApprovalReentrancyTest} from "../methods/debt-share-token/SetReceiverApprovalReentrancyTest.sol";
import {DecreaseReceiveAllowanceReentrancyTest} from
    "../methods/debt-share-token/DecreaseReceiveAllowanceReentrancyTest.sol";
import {IncreaseReceiveAllowanceReentrancyTest} from
    "../methods/debt-share-token/IncreaseReceiveAllowanceReentrancyTest.sol";
import {ReceiveAllowanceReentrancyTest} from "../methods/debt-share-token/ReceiveAllowanceReentrancyTest.sol";

contract DebtShareTokenMethodsRegistry is ShareTokenMethodsRegistry {
    constructor() {
        _registerMethod(new TransferReentrancyTest());
        _registerMethod(new TransferFromReentrancyTest());
        _registerMethod(new SetReceiverApprovalReentrancyTest());
        _registerMethod(new DecreaseReceiveAllowanceReentrancyTest());
        _registerMethod(new IncreaseReceiveAllowanceReentrancyTest());
        _registerMethod(new ReceiveAllowanceReentrancyTest());
    }

    function abiFile() external pure override returns (string memory) {
        return "/cache/foundry/out/silo-core/ShareDebtToken.sol/ShareDebtToken.json";
    }
}
