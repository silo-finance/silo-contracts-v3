// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMethodReentrancyTest} from "../interfaces/IMethodReentrancyTest.sol";
import {IMethodsRegistry} from "../interfaces/IMethodsRegistry.sol";

import {DomainSeparatorReentrancyTest} from "../methods/share-token/DomainSeparatorReentrancyTest.sol";
import {AllowanceReentrancyTest} from "../methods/share-token/AllowanceReentrancyTest.sol";
import {ApproveReentrancyTest} from "../methods/share-token/ApproveReentrancyTest.sol";
import {BalanceOfReentrancyTest} from "../methods/share-token/BalanceOfReentrancyTest.sol";
import {BalanceOfAndTotalSupplyReentrancyTest} from "../methods/share-token/BalanceOfAndTotalSupplyReentrancyTest.sol";
import {BurnReentrancyTest} from "../methods/share-token/BurnReentrancyTest.sol";
import {CallOnBehalfOfShareTokenReentrancyTest} from
    "../methods/share-token/CallOnBehalfOfShareTokenReentrancyTest.sol";
import {DecimalsReentrancyTest} from "../methods/share-token/DecimalsReentrancyTest.sol";
import {DecimalsOffsetReentrancyTest} from "../methods/share-token/DecimalsOffsetReentrancyTest.sol";
import {Eip712DomainReentrancyTest} from "../methods/share-token/Eip712DomainReentrancyTest.sol";
import {ForwardTransferFromNoChecksReentrancyTest} from
    "../methods/share-token/ForwardTransferFromNoChecksReentrancyTest.sol";
import {HookReceiverReentrancyTest} from "../methods/share-token/HookReceiverReentrancyTest.sol";
import {HookSetupReentrancyTest} from "../methods/share-token/HookSetupReentrancyTest.sol";
import {InitializeReentrancyTest} from "../methods/share-token/InitializeReentrancyTest.sol";
import {MintReentrancyTest} from "../methods/share-token/MintReentrancyTest.sol";
import {NameReentrancyTest} from "../methods/share-token/NameReentrancyTest.sol";
import {NoncesReentrancyTest} from "../methods/share-token/NoncesReentrancyTest.sol";
import {PermitReentrancyTest} from "../methods/share-token/PermitReentrancyTest.sol";
import {SiloReentrancyTest} from "../methods/share-token/SiloReentrancyTest.sol";
import {SiloConfigReentrancyTest} from "../methods/share-token/SiloConfigReentrancyTest.sol";
import {SymbolReentrancyTest} from "../methods/share-token/SymbolReentrancyTest.sol";
import {SynchronizeHooksReentrancyTest} from "../methods/share-token/SynchronizeHooksReentrancyTest.sol";
import {TotalSupplyReentrancyTest} from "../methods/share-token/TotalSupplyReentrancyTest.sol";
import {VersionReentrancyTest} from "../methods/silo-hook-v2/VersionReentrancyTest.sol";

abstract contract ShareTokenMethodsRegistry is IMethodsRegistry {
    mapping(bytes4 methodSig => IMethodReentrancyTest) public methods;
    bytes4[] public supportedMethods;

    constructor() {
        _registerMethod(new DomainSeparatorReentrancyTest());
        _registerMethod(new AllowanceReentrancyTest());
        _registerMethod(new ApproveReentrancyTest());
        _registerMethod(new BalanceOfReentrancyTest());
        _registerMethod(new BalanceOfAndTotalSupplyReentrancyTest());
        _registerMethod(new BurnReentrancyTest());
        _registerMethod(new CallOnBehalfOfShareTokenReentrancyTest());
        _registerMethod(new DecimalsReentrancyTest());
        _registerMethod(new DecimalsOffsetReentrancyTest());
        _registerMethod(new Eip712DomainReentrancyTest());
        _registerMethod(new ForwardTransferFromNoChecksReentrancyTest());
        _registerMethod(new HookReceiverReentrancyTest());
        _registerMethod(new HookSetupReentrancyTest());
        _registerMethod(new InitializeReentrancyTest());
        _registerMethod(new MintReentrancyTest());
        _registerMethod(new NameReentrancyTest());
        _registerMethod(new NoncesReentrancyTest());
        _registerMethod(new PermitReentrancyTest());
        _registerMethod(new SiloReentrancyTest());
        _registerMethod(new SiloConfigReentrancyTest());
        _registerMethod(new SymbolReentrancyTest());
        _registerMethod(new SynchronizeHooksReentrancyTest());
        _registerMethod(new TotalSupplyReentrancyTest());
        _registerMethod(new VersionReentrancyTest());

    }

    function supportedMethodsLength() external view returns (uint256) {
        return supportedMethods.length;
    }

    function abiFile() external pure virtual returns (string memory) {}

    function _registerMethod(IMethodReentrancyTest method) internal {
        methods[method.methodSignature()] = method;
        supportedMethods.push(method.methodSignature());
    }
}
