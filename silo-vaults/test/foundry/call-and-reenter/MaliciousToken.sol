// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Registries} from "./registries/Registries.sol";
import {IMethodsRegistry} from "silo-core/test/foundry/Silo/reentrancy/interfaces/IMethodsRegistry.sol";
import {IMethodReentrancyTest} from "silo-core/test/foundry/Silo/reentrancy/interfaces/IMethodReentrancyTest.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";

import {TestStateLib} from "./TestState.sol";

contract MaliciousToken is MintableToken, Test {
    IMethodsRegistry[] internal _methodRegistries;

    constructor() MintableToken(18) {
        Registries registries = new Registries();
        _methodRegistries = registries.list();
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _tryToReenter();

        super.transfer(recipient, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _tryToReenter();

        super.transferFrom(sender, recipient, amount);

        return true;
    }

    function _tryToReenter() internal {
        if (!TestStateLib.reenter()) return;

        // It will reenter from two places:
        // 1. When vault transfers tokens
        // 2. When market transfers tokens
        emit log_string("\tTrying to reenter:");

        ISiloVault vault = TestStateLib.vault();

        bool entered = vault.reentrancyGuardEntered();
        assertTrue(entered, "Reentrancy is not enabled on a token transfer");

        TestStateLib.disableReentrancy();

        uint256 stateBeforeReentrancyTest = vm.snapshotState();

        for (uint j = 0; j < _methodRegistries.length; j++) {
            uint256 totalMethods = _methodRegistries[j].supportedMethodsLength();

            for (uint256 i = 0; i < totalMethods; i++) {
                bytes4 methodSig = _methodRegistries[j].supportedMethods(i);
                IMethodReentrancyTest method = _methodRegistries[j].methods(methodSig);

                emit log_string(string.concat("\t  ", method.methodDescription()));

                method.verifyReentrancy();

                vm.revertToState(stateBeforeReentrancyTest);
            }
        }

        TestStateLib.enableReentrancy();
    }
}
