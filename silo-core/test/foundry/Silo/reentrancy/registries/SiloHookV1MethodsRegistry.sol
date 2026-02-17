// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMethodReentrancyTest} from "../interfaces/IMethodReentrancyTest.sol";
import {IMethodsRegistry} from "../interfaces/IMethodsRegistry.sol";

import {AcceptOwnershipReentrancyTest} from "../methods/silo-hook-v1/AcceptOwnershipReentrancyTest.sol";
import {AfterActionReentrancyTest} from "../methods/silo-hook-v1/AfterActionReentrancyTest.sol";
import {BeforeActionReentrancyTest} from "../methods/silo-hook-v1/BeforeActionReentrancyTest.sol";
import {ConfiguredGaugesReentrancyTest} from "../methods/silo-hook-v1/ConfiguredGaugesReentrancyTest.sol";
import {HookReceiverConfigReentrancyTest} from "../methods/silo-hook-v1/HookReceiverConfigReentrancyTest.sol";
import {InitializeReentrancyTest} from "../methods/silo-hook-v1/InitializeReentrancyTest.sol";
import {MaxLiquidationReentrancyTest} from "../methods/silo-hook-v1/MaxLiquidationReentrancyTest.sol";
import {OwnerReentrancyTest} from "../methods/silo-hook-v1/OwnerReentrancyTest.sol";
import {PendingOwnerReentrancyTest} from "../methods/silo-hook-v1/PendingOwnerReentrancyTest.sol";
import {LiquidationCallReentrancyTest} from "../methods/silo-hook-v1/LiquidationCallReentrancyTest.sol";
import {RemoveGaugeReentrancyTest} from "../methods/silo-hook-v1/RemoveGaugeReentrancyTest.sol";
import {RenounceOwnershipReentrancyTest} from "../methods/silo-hook-v1/RenounceOwnershipReentrancyTest.sol";
import {SetGaugeReentrancyTest} from "../methods/silo-hook-v1/SetGaugeReentrancyTest.sol";
import {SiloConfigReentrancyTest} from "../methods/silo-hook-v1/SiloConfigReentrancyTest.sol";
import {TransferOwnershipReentrancyTest} from "../methods/silo-hook-v1/TransferOwnershipReentrancyTest.sol";
import {TransferOwnership1StepReentrancyTest} from "../methods/silo-hook-v1/TransferOwnership1StepReentrancyTest.sol";

contract SiloHookV1MethodsRegistry is IMethodsRegistry {
    mapping(bytes4 methodSig => IMethodReentrancyTest) public methods;
    bytes4[] public supportedMethods;

    constructor() {
        _registerMethod(new AcceptOwnershipReentrancyTest());
        _registerMethod(new AfterActionReentrancyTest());
        _registerMethod(new BeforeActionReentrancyTest());
        _registerMethod(new ConfiguredGaugesReentrancyTest());
        _registerMethod(new HookReceiverConfigReentrancyTest());
        _registerMethod(new InitializeReentrancyTest());
        _registerMethod(new MaxLiquidationReentrancyTest());
        _registerMethod(new OwnerReentrancyTest());
        _registerMethod(new PendingOwnerReentrancyTest());
        _registerMethod(new LiquidationCallReentrancyTest());
        _registerMethod(new RemoveGaugeReentrancyTest());
        _registerMethod(new RenounceOwnershipReentrancyTest());
        _registerMethod(new SetGaugeReentrancyTest());
        _registerMethod(new SiloConfigReentrancyTest());
        _registerMethod(new TransferOwnershipReentrancyTest());
        _registerMethod(new TransferOwnership1StepReentrancyTest());
    }

    function supportedMethodsLength() external view returns (uint256) {
        return supportedMethods.length;
    }

    function abiFile() external pure virtual returns (string memory) {
        return "/cache/foundry/out/silo-core/SiloHookV1.sol/SiloHookV1.json";
    }

    function _registerMethod(IMethodReentrancyTest method) internal {
        methods[method.methodSignature()] = method;
        supportedMethods.push(method.methodSignature());
    }
}
