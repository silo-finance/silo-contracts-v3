// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMethodsRegistry} from "../interfaces/IMethodsRegistry.sol";
import {SiloMethodsRegistry} from "./SiloMethodsRegistry.sol";
import {SiloConfigMethodsRegistry} from "./SiloConfigMethodsRegistry.sol";
import {CollateralShareTokenMethodsRegistry} from "./CollateralShareTokenMethodsRegistry.sol";
import {DebtShareTokenMethodsRegistry} from "./DebtShareTokenMethodsRegistry.sol";
import {SiloHookV1MethodsRegistry} from "./SiloHookV1MethodsRegistry.sol";
import {SiloHookV2MethodsRegistry} from "./SiloHookV2MethodsRegistry.sol";
import {LeverageMethodsRegistry} from "./LeverageMethodsRegistry.sol";

contract Registries {
    IMethodsRegistry[] public registry;

    constructor() {
        registry.push(IMethodsRegistry(address(new SiloMethodsRegistry())));
        registry.push(IMethodsRegistry(address(new SiloConfigMethodsRegistry())));
        registry.push(IMethodsRegistry(address(new CollateralShareTokenMethodsRegistry())));
        registry.push(IMethodsRegistry(address(new DebtShareTokenMethodsRegistry())));
        registry.push(IMethodsRegistry(address(new SiloHookV1MethodsRegistry())));
        registry.push(IMethodsRegistry(address(new SiloHookV2MethodsRegistry())));
        registry.push(IMethodsRegistry(address(new LeverageMethodsRegistry())));
    }

    function list() external view returns (IMethodsRegistry[] memory) {
        return registry;
    }
}
