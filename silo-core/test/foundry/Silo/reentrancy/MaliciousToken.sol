// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ERC20} from "openzeppelin5/token/ERC20/ERC20.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {Registries} from "./registries/Registries.sol";
import {LeverageMethodsRegistry} from "./registries/LeverageMethodsRegistry.sol";
import {IMethodsRegistry} from "./interfaces/IMethodsRegistry.sol";
import {IMethodReentrancyTest} from "./interfaces/IMethodReentrancyTest.sol";
import {TestStateLib} from "./TestState.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {Tabs} from "../../_common/Tabs.sol";

contract MaliciousToken is MintableToken, Test, Tabs {
    IMethodsRegistry[] internal _methodRegistries;
    LeverageMethodsRegistry internal _leverageMethodsRegistry;

    constructor() MintableToken(18) {
        Registries registries = new Registries();
        _methodRegistries = registries.list();
        _leverageMethodsRegistry = new LeverageMethodsRegistry();
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _tryToReenter();

        onDemand = true; // to fight with ERC20InsufficientBalance

        super.transfer(recipient, amount);

        onDemand = false;

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _tryToReenter();

        onDemand = true; // to fight with ERC20InsufficientBalance
        super.transferFrom(sender, recipient, amount);
        onDemand = false;

        return true;
    }

    function _tryToReenter() internal {
        if (!TestStateLib.reenter() && !TestStateLib.leverageReenter()) return;

        // reenter before transfer
        console2.log(_tabs(1), "Trying to reenter:");

        ISiloConfig config = TestStateLib.siloConfig();

        if (TestStateLib.reenter()) {
            bool entered = config.reentrancyGuardEntered();
            assertTrue(entered, "Reentrancy is not enabled on a token transfer");

            TestStateLib.disableReentrancy();
            _callAllMethods();
            TestStateLib.enableReentrancy();
        }

        console2.log(_tabs(1), "Trying to reenter: leverage");

        if (TestStateLib.leverageReenter()) {
            // address leverageRouter = TestStateLib.leverageRouter();

            // bool entered = TransientReentrancy(leverage).reentrancyGuardEntered();
            // assertTrue(entered, "Reentrancy is not enabled on a token transfer when leverage");

            TestStateLib.disableLeverageReentrancy();
            _callOnlyLeverageMethods();
            TestStateLib.enableLeverageReentrancy();
        }

        console2.log(_tabs(1), "Trying to reenter - done\n");
    }

    function _callAllMethods() internal {
        console2.log(_tabs(2), "[MaliciousToken] calling all methods");

        uint256 stateBeforeReentrancyTest = vm.snapshotState();

        for (uint256 j = 0; j < _methodRegistries.length; j++) {
            console2.log(_tabs(3, "[_callAllMethods] calling [%s] %s"), j, _methodRegistries[j].abiFile());

            if (Strings.equal(_methodRegistries[j].abiFile(), _leverageMethodsRegistry.abiFile())) continue;

            uint256 totalMethods = _methodRegistries[j].supportedMethodsLength();

            for (uint256 i = 0; i < totalMethods; i++) {
                bytes4 methodSig = _methodRegistries[j].supportedMethods(i);
                IMethodReentrancyTest method = _methodRegistries[j].methods(methodSig);

                // console2.log(_tabs(4, "[_callAllMethods] loop [%s] %s"), i, method.methodDescription());

                method.verifyReentrancy();

                vm.revertToState(stateBeforeReentrancyTest);
            }

            console2.log(_tabs(3, "[_callAllMethods] calling abi done"));
        }

        console2.log(_tabs(2), "[MaliciousToken] calling all methods - done\n");
    }

    function _callOnlyLeverageMethods() internal {
        console2.log(_tabs(2), "[MaliciousToken] calling only leverage methods");

        uint256 stateBeforeReentrancyTest = vm.snapshotState();

        uint256 totalMethods = _leverageMethodsRegistry.supportedMethodsLength();

        for (uint256 i = 0; i < totalMethods; i++) {
            bytes4 methodSig = _leverageMethodsRegistry.supportedMethods(i);
            IMethodReentrancyTest method = _leverageMethodsRegistry.methods(methodSig);

            // console2.log(_tabs(3), method.methodDescription());

            method.verifyReentrancy();

            vm.revertToState(stateBeforeReentrancyTest);
        }

        console2.log(_tabs(2), "[MaliciousToken] calling only leverage methods - done\n");
    }
}
