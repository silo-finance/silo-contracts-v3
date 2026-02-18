// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";

import {AddrKey} from "common/addresses/AddrKey.sol";
import {Registries} from "./registries/Registries.sol";
import {IMethodsRegistry} from "./interfaces/IMethodsRegistry.sol";
import {MaliciousToken} from "./MaliciousToken.sol";
import {TestStateLib} from "./TestState.sol";
import {IMethodReentrancyTest} from "./interfaces/IMethodReentrancyTest.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy} from
    "silo-core/deploy/LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy.s.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloReentrancyTest
*/
contract SiloReentrancyTest is Test {
    ISiloConfig public siloConfig;

    mapping(string abiFile => string[] methods) public methodsNotFound;

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_coverage_for_reentrancy
    */
    function test_coverage_for_reentrancy() public {
        Registries registries = new Registries();
        IMethodsRegistry[] memory methodRegistries = registries.list();

        bool allCovered = true;
        string memory root = vm.projectRoot();

        for (uint256 j = 0; j < methodRegistries.length; j++) {
            string memory abiPath = string.concat(root, methodRegistries[j].abiFile());
            string memory json = vm.readFile(abiPath);

            string[] memory keys = vm.parseJsonKeys(json, ".methodIdentifiers");

            for (uint256 i = 0; i < keys.length; i++) {
                bytes4 sig = bytes4(keccak256(bytes(keys[i])));
                address method = address(methodRegistries[j].methods(sig));

                if (method == address(0)) {
                    allCovered = false;

                    emit log_string(string.concat("\nABI: ", abiPath));
                    emit log_string(string.concat("Method not found: ", keys[i]));
                    methodsNotFound[abiPath].push(keys[i]);
                }
            }
        }

        if (!allCovered) {
            console2.log("\n----------- All methods should be covered, not found: -------------\n");
        }

        for (uint256 j = 0; j < methodRegistries.length; j++) {
            string memory abiPath = string.concat(root, methodRegistries[j].abiFile());

            string[] memory methods = methodsNotFound[abiPath];
            if (methods.length == 0) continue;

            console2.log("\nABI: %s\nMethods not found:", abiPath);

            for (uint256 i = 0; i < methods.length; i++) {
                console2.log("- ", methods[i]);
            }
        }

        assertTrue(allCovered, "All methods should be covered");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_reentrancy -vv
    */
    function test_reentrancy() public {
        _deploySiloWithOverrides();
        Registries registries = new Registries();
        IMethodsRegistry[] memory methodRegistries = registries.list();

        emit log_string("\n\nRunning reentrancy test");

        uint256 stateBeforeTest = vm.snapshotState();

        for (uint256 j = 0; j < methodRegistries.length; j++) {
            uint256 totalMethods = methodRegistries[j].supportedMethodsLength();

            console2.log("\nVerifying [%s] %s", j, methodRegistries[j].abiFile());

            for (uint256 i = 0; i < totalMethods; i++) {
                bytes4 methodSig = methodRegistries[j].supportedMethods(i);
                IMethodReentrancyTest method = methodRegistries[j].methods(methodSig);

                console2.log("\nExecute [%s/%s] %s", j, i, method.methodDescription());

                bool entered = siloConfig.reentrancyGuardEntered();
                assertTrue(!entered, "Reentrancy should be disabled before calling the method");

                method.callMethod();

                entered = siloConfig.reentrancyGuardEntered();
                assertTrue(!entered, "Reentrancy should be disabled after calling the method");

                vm.revertToState(stateBeforeTest);
                console2.log("Execute [%s/%s] %s - done\n", j, i, method.methodDescription());
            }

            console2.log("Verifying [%s] %s - done\n", j, methodRegistries[j].abiFile());
        }
    }

    function _deploySiloWithOverrides() internal {
        SiloFixture siloFixture = new SiloFixture();

        SiloConfigOverride memory configOverride;

        configOverride.token0 = address(new MaliciousToken());
        configOverride.token1 = address(new MaliciousToken());
        configOverride.configName = SiloConfigsNames.SILO_LOCAL_NOT_BORROWABLE;
        ISilo silo0;
        ISilo silo1;
        address hookReceiver;

        (siloConfig, silo0, silo1,,, hookReceiver) = siloFixture.deploy_local(configOverride);

        AddrLib.setAddress(AddrKey.DAO, makeAddr("DAO"));

        LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy leverageDeploy =
            new LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy();

        leverageDeploy.disableDeploymentsSync();
        address leverageRouter = address(leverageDeploy.run());

        _createIncentiveController(hookReceiver, address(silo0));

        TestStateLib.init(
            address(siloConfig),
            address(silo0),
            address(silo1),
            configOverride.token0,
            configOverride.token1,
            hookReceiver,
            leverageRouter
        );
    }

    function _createIncentiveController(address _hookReceiver, address _debtSilo) internal {
        ISiloIncentivesController gauge = new SiloIncentivesControllerCompatible(makeAddr("DAO"), _hookReceiver, _debtSilo);

        address owner = Ownable(_hookReceiver).owner();
        vm.prank(owner);
        IGaugeHookReceiver(_hookReceiver).setGauge(gauge, IShareToken(_debtSilo));
    }
}
